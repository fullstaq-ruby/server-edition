#!/usr/bin/env ruby
# frozen_string_literal: true

# Prune EOL Ruby version packages from the APT repository state.
#
# Removes packages for Ruby versions no longer in config.yml from all
# distro repos in the Aptly state, then compacts and re-uploads.
#
# Usage:
#   PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
#   ./internal-scripts/ci-cd/archive/prune-apt-packages.rb [--dry-run]
#
# Automatically detects which Ruby versions are EOL by comparing
# packages in the Aptly state against minor_version_packages in config.yml.

require_relative '../../../lib/gcloud_storage_lock'
require_relative '../../../lib/ci_workflow_support'
require_relative '../../../lib/shell_scripting_support'
require_relative '../../../lib/publishing_support'
require 'json'
require 'shellwords'
require 'tmpdir'
require 'set'
require 'fileutils'
require 'optparse'

class PruneAptPackages
  REPO_ORIGIN = 'Fullstaq-Ruby'
  REPO_LABEL = 'Fullstaq-Ruby'

  # Matches: fullstaq-ruby-3.1, fullstaq-ruby-3.1-jemalloc, fullstaq-ruby-3.1.7, etc.
  # Does NOT match: fullstaq-ruby-common, fullstaq-rbenv
  RUBY_PACKAGE_PATTERN = /\Afullstaq-ruby-(\d+\.\d+)/

  include CiWorkflowSupport
  include ShellScriptingSupport
  include PublishingSupport

  def main
    parse_options
    require_envvar 'PRODUCTION_REPO_BUCKET_NAME'

    print_header 'Initializing'
    load_config
    create_temp_dirs
    ensure_gpg_state_isolated
    activate_wrappers_bin_dir
    initialize_aptly
    fetch_and_import_signing_key

    print_header 'Downloading repository state'
    version = get_latest_production_repo_version
    if version == 0
      abort 'ERROR: No production repository exists yet'
    end
    fetch_state(version)

    print_header 'Identifying EOL Ruby versions'
    active_minors = active_ruby_minor_versions
    log_info "Active Ruby minor versions: #{active_minors.join(', ')}"

    print_header 'Scanning packages'
    total_pruned = 0
    repos = list_aptly_repos
    repos.each do |distro|
      pruned = prune_eol_packages_from_repo(distro, active_minors)
      total_pruned += pruned
    end

    if total_pruned == 0
      log_notice 'No EOL Ruby packages found to prune'
      exit
    end

    log_notice "Total packages to prune: #{total_pruned}"

    if @dry_run
      log_notice 'DRY RUN — not uploading changes'
      exit
    end

    print_header 'Compacting state'
    compact_state

    print_header 'Re-publishing repository'
    repos.each do |distro|
      publish_repo(distro)
    end

    print_header 'Archiving and uploading state'
    archive_state
    upload_state(version + 1)
    upload_repo(version + 1, version)
    create_version_note(version + 1)
    declare_latest_version(version + 1)

    print_header 'Success!'
    log_info "Pruned #{total_pruned} packages across #{repos.size} repos"
    log_info "Main repo: version #{version} -> #{version + 1}"

    cleanup
  end

private
  def parse_options
    @dry_run = false
    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"
      opts.on('--dry-run', 'Do not upload changes') { @dry_run = true }
    end.parse!
  end

  def create_temp_dirs
    @temp_dir = Dir.mktmpdir('apt-prune')
    @wrappers_bin_dir = "#{@temp_dir}/wrappers"
    @aptly_config_path = "#{@temp_dir}/aptly.conf"
    @signing_key_path = "#{@temp_dir}/key.gpg"
    @local_state_path = "#{@temp_dir}/state"
    @local_state_db_path = "#{@local_state_path}/db"
    @local_state_repo_path = "#{@local_state_path}/repo"
    @local_state_archive_path = "#{@temp_dir}/state.tar.zst"

    Dir.mkdir(@wrappers_bin_dir)
    FileUtils.mkdir_p(@local_state_db_path)
    FileUtils.mkdir_p(@local_state_repo_path)
  end

  def ensure_gpg_state_isolated
    File.open("#{@wrappers_bin_dir}/gpg", 'w:utf-8') do |f|
      f.write("#!/bin/sh\n")
      f.write(
        sprintf("exec %s --homedir %s \"$@\"\n",
          Shellwords.escape(find_gpg),
          Shellwords.escape(@temp_dir))
      )
    end
    File.chmod(0755, "#{@wrappers_bin_dir}/gpg")
  end

  def find_gpg
    ENV['PATH'].split(':').each do |dir|
      next if dir == @wrappers_bin_dir
      candidate = "#{dir}/gpg"
      return candidate if File.exist?(candidate)
    end
    abort('GPG not found')
  end

  def activate_wrappers_bin_dir
    ENV['PATH'] = "#{@wrappers_bin_dir}:#{ENV['PATH']}"
  end

  def initialize_aptly
    File.open(@aptly_config_path, 'w:utf-8') do |f|
      f.write(JSON.generate(
        rootDir: @local_state_path,
        FileSystemPublishEndpoints: {
          main: {
            rootDir: @local_state_repo_path,
            linkMethod: 'symlink',
            verifyMethod: 'md5'
          }
        }
      ))
    end
  end

  def fetch_and_import_signing_key
    log_notice 'Fetching and importing signing key'
    File.open(@signing_key_path, 'wb') do |f|
      f.write(fetch_signing_key)
    end
    @gpg_key_id = infer_gpg_key_id(@temp_dir, @signing_key_path)
    log_info "Signing key ID: #{@gpg_key_id}"
    import_gpg_key(@temp_dir, @signing_key_path)
  end

  def latest_production_version_note_url
    "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/latest_version.txt"
  end

  def fetch_state(version)
    log_notice "Fetching state version #{version}"
    run_bash(
      sprintf('gsutil -m cp %s - | zstd -dc | tar -xC %s',
        Shellwords.escape("gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/#{version}/state.tar.zst"),
        Shellwords.escape(@local_state_path)),
      pipefail: true,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def active_ruby_minor_versions
    config['ruby']['minor_version_packages'].map { |p| p['minor_version'] }
  end

  def list_aptly_repos
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'repo', 'list',
      "-config=#{@aptly_config_path}", '-raw',
      log_invocation: true, check_error: true
    )
    stdout_output.split("\n").map(&:strip).reject(&:empty?)
  end

  def list_packages(distro)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'repo', 'show',
      "-config=#{@aptly_config_path}",
      '-with-packages', distro,
      log_invocation: false, check_error: true
    )
    stdout_output.sub!(/.*^Packages:$/m, '')
    stdout_output.split("\n").map(&:strip).reject(&:empty?)
  end

  def prune_eol_packages_from_repo(distro, active_minors)
    packages = list_packages(distro)
    eol_packages = packages.select do |pkg|
      if pkg =~ RUBY_PACKAGE_PATTERN
        minor = $1
        !active_minors.include?(minor)
      else
        false
      end
    end

    if eol_packages.empty?
      log_info "[#{distro}] No EOL packages found"
      return 0
    end

    log_notice "[#{distro}] Pruning #{eol_packages.size} EOL packages (of #{packages.size} total)"
    eol_packages.each { |pkg| log_info "  #{YELLOW}PRUNE#{RESET} #{pkg}" }

    if !@dry_run
      eol_packages.each_slice(50) do |batch|
        query = batch.join(' | ')
        run_command(
          'aptly', 'repo', 'remove',
          "-config=#{@aptly_config_path}",
          distro, query,
          log_invocation: false,
          check_error: true
        )
      end
    end

    eol_packages.size
  end

  def compact_state
    run_command(
      'aptly', 'db', 'cleanup',
      "-config=#{@aptly_config_path}", '-verbose',
      log_invocation: true, check_error: true, passthru_output: true
    )
  end

  def publish_repo(distro)
    log_notice "[#{distro}] Publishing"
    _, stderr_output, status = run_command_capture_output(
      'aptly', 'publish', 'repo',
      '-batch', '-force-overwrite',
      "-config=#{@aptly_config_path}",
      "-gpg-key=#{@gpg_key_id}",
      "-distribution=#{distro}",
      "-origin=#{REPO_ORIGIN}",
      "-label=#{REPO_LABEL}",
      distro, 'filesystem:main:.',
      log_invocation: true, check_error: false
    )
    if !status.success?
      if stderr_output =~ /unable to figure out list of architectures/
        run_command(
          'aptly', 'publish', 'repo',
          '-batch', '-force-overwrite', '-architectures=all',
          "-config=#{@aptly_config_path}",
          "-gpg-key=#{@gpg_key_id}",
          "-distribution=#{distro}",
          "-origin=#{REPO_ORIGIN}",
          "-label=#{REPO_LABEL}",
          distro, 'filesystem:main:.',
          log_invocation: true, check_error: true
        )
      else
        abort("ERROR publishing #{distro}: #{stderr_output.chomp}")
      end
    end
  end

  def archive_state
    log_notice 'Creating state archive'
    run_bash(
      sprintf("tar -C %s -cf - . | zstd -T0 > %s",
        Shellwords.escape(@local_state_path),
        Shellwords.escape(@local_state_archive_path)),
      pipefail: true,
      log_invocation: true, check_error: true, passthru_output: true
    )
  end

  def upload_state(version)
    bucket = ENV['PRODUCTION_REPO_BUCKET_NAME']
    run_command(
      'gsutil', '-h', 'Cache-Control:public', 'cp',
      @local_state_archive_path,
      "gs://#{bucket}/versions/#{version}/state.tar.zst",
      log_invocation: true, check_error: true, passthru_output: true
    )
  end

  def upload_repo(version, old_version)
    bucket = ENV['PRODUCTION_REPO_BUCKET_NAME']

    log_notice "Copying repo version #{old_version} to #{version}"
    run_command(
      'gsutil', '-m', '-h', 'Cache-Control:public',
      'rsync', '-r', '-d',
      "gs://#{bucket}/versions/#{old_version}/public",
      "gs://#{bucket}/versions/#{version}/public",
      log_invocation: true, check_error: true, passthru_output: true
    )

    log_notice "Uploading pruned repo as version #{version}"
    run_command(
      'gsutil', '-m', '-h', 'Cache-Control:public',
      'rsync', '-r', '-d',
      @local_state_repo_path,
      "gs://#{bucket}/versions/#{version}/public",
      log_invocation: true, check_error: true, passthru_output: true
    )
  end

  def create_version_note(version)
    run_bash(
      sprintf('gsutil -q -h Content-Type:text/plain -h Cache-Control:public cp - %s <<<%s',
        Shellwords.escape("gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/#{version}/version.txt"),
        Shellwords.escape(version.to_s)),
      log_invocation: true, check_error: true, pipefail: false
    )
  end

  def declare_latest_version(version)
    log_notice "Activating version #{version}"
    run_bash(
      sprintf('gsutil -q -h Content-Type:text/plain -h Cache-Control:no-store cp - %s <<<%s',
        Shellwords.escape("gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/latest_version.txt"),
        Shellwords.escape(version.to_s)),
      log_invocation: true, check_error: true, pipefail: false
    )
  end

  def cleanup
    log_info "Cleaning up #{@temp_dir}"
    FileUtils.remove_entry_secure(@temp_dir)
  end
end

PruneAptPackages.new.main
