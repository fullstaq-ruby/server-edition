#!/usr/bin/env ruby
# frozen_string_literal: true

# Prune EOL Ruby version packages from the YUM repository.
#
# Removes RPM files for Ruby versions no longer in config.yml from all
# distro/arch directories, regenerates repodata, and re-uploads.
#
# Usage:
#   PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
#   ./internal-scripts/ci-cd/archive/prune-yum-packages.rb [--dry-run]

require_relative '../../../lib/gcloud_storage_lock'
require_relative '../../../lib/ci_workflow_support'
require_relative '../../../lib/shell_scripting_support'
require_relative '../../../lib/publishing_support'
require 'shellwords'
require 'tmpdir'
require 'fileutils'
require 'optparse'

class PruneYumPackages
  # Matches: fullstaq-ruby-3.1.7-jemalloc-rev1-centos8.x86_64.rpm
  RUBY_RPM_PATTERN = /\Afullstaq-ruby-(\d+\.\d+)/

  include CiWorkflowSupport
  include ShellScriptingSupport
  include PublishingSupport

  def main
    parse_options
    require_envvar 'PRODUCTION_REPO_BUCKET_NAME'

    print_header 'Initializing'
    load_config
    create_temp_dirs
    initialize_locking
    pull_utility_image_if_not_exists
    fetch_and_import_signing_key

    total_pruned = 0
    version = nil

    begin
      synchronize do
        print_header 'Downloading repository'
        version = get_latest_production_repo_version
        if version == 0
          abort 'ERROR: No production repository exists yet'
        end
        fetch_repo(version)

        print_header 'Identifying EOL Ruby versions'
        active_minors = active_ruby_minor_versions
        log_info "Active Ruby minor versions: #{active_minors.join(', ')}"

        print_header 'Scanning and pruning packages'
        affected_dirs = []

        Dir.glob("#{@local_repo_path}/*/*").each do |arch_dir|
          next unless File.directory?(arch_dir)
          distro = File.basename(File.dirname(arch_dir))
          arch = File.basename(arch_dir)

          rpms = Dir.glob("#{arch_dir}/fullstaq-ruby-*.rpm")
          eol_rpms = rpms.select do |rpm|
            basename = File.basename(rpm)
            if basename =~ RUBY_RPM_PATTERN
              !active_minors.include?($1)
            else
              false
            end
          end

          next if eol_rpms.empty?

          log_notice "[#{distro}/#{arch}] Pruning #{eol_rpms.size} EOL packages (of #{rpms.size} total)"
          eol_rpms.each { |rpm| log_info "  #{YELLOW}PRUNE#{RESET} #{File.basename(rpm)}" }
          total_pruned += eol_rpms.size

          if !@dry_run
            eol_rpms.each { |rpm| File.delete(rpm) }
            affected_dirs << arch_dir
          end
        end

        if total_pruned == 0
          log_notice 'No EOL Ruby packages found to prune'
          return
        end

        log_notice "Total packages pruned: #{total_pruned}"

        if @dry_run
          log_notice 'DRY RUN — not uploading changes'
          return
        end

        print_header 'Regenerating repo metadata'
        affected_dirs.each do |dir|
          invoke_createrepo(dir)
          sign_repo(dir)
        end
        check_lock_health

        print_header 'Uploading pruned repository'
        upload_repo(version + 1, version)
        create_version_note(version + 1)
        declare_latest_version(version + 1)
      end

      print_header 'Success!'
      if total_pruned > 0 && !@dry_run
        log_info "Pruned #{total_pruned} packages"
        log_info "Main repo: version #{version} -> #{version + 1}"
      end
    ensure
      cleanup
    end
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
    @temp_dir = Dir.mktmpdir('yum-prune')
    @local_repo_path = "#{@temp_dir}/repo"
    @signing_key_path = "#{@temp_dir}/key.gpg"
    Dir.mkdir(@local_repo_path)
  end

  def initialize_locking
    @lock = GCloudStorageLock.new(url: lock_url)
  end

  def lock_url
    "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/locks/yum"
  end

  def synchronize(&block)
    @lock.synchronize(&block)
  end

  def check_lock_health
    abort 'ERROR: lock is unhealthy. Aborting operation' if !@lock.healthy?
  end

  def fetch_and_import_signing_key
    log_notice 'Fetching and importing signing key'
    File.open(@signing_key_path, 'wb') do |f|
      f.write(fetch_signing_key)
    end
    @gpg_key_id = infer_gpg_key_id(@temp_dir, @signing_key_path)
    import_gpg_key(@temp_dir, @signing_key_path)
  end

  def latest_production_version_note_url
    "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/latest_version.txt"
  end

  def fetch_repo(version)
    run_command(
      'gsutil', '-m', 'rsync', '-r',
      "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/#{version}/public",
      @local_repo_path,
      log_invocation: true, check_error: true, passthru_output: true
    )
  end

  def active_ruby_minor_versions
    config['ruby']['minor_version_packages'].map { |p| p['minor_version'] }
  end

  def invoke_createrepo(dir)
    run_command(
      'docker', 'run', '--rm',
      '-v', "#{dir}:/input:delegated",
      '--user', "#{Process.uid}:#{Process.gid}",
      utility_image_name,
      'createrepo_c', '--update', '/input',
      log_invocation: true, check_error: true
    )
  end

  def sign_repo(path)
    run_command(
      'gpg', "--homedir=#{@temp_dir}", "--local-user=#{@gpg_key_id}",
      '--batch', '--yes', '--detach-sign', '--armor',
      "#{path}/repodata/repomd.xml",
      log_invocation: true, check_error: true
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
      @local_repo_path,
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

PruneYumPackages.new.main
