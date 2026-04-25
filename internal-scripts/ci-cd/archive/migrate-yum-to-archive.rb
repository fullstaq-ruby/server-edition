#!/usr/bin/env ruby
# frozen_string_literal: true

# Incremental migration script to move EOL distribution packages
# from the main YUM repository to the archive YUM repository.
# Safe to run repeatedly — merges new EOL distros into the existing archive.
#
# Usage:
#   PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
#   ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo-archive \
#   ./internal-scripts/ci-cd/archive/migrate-yum-to-archive.rb [--dry-run] [--distros centos-8]
#
# If --distros is not specified, automatically detects EOL distros by comparing
# the repo contents against the current environments/ directory.

require_relative '../../../lib/ci_workflow_support'
require_relative '../../../lib/shell_scripting_support'
require_relative '../../../lib/publishing_support'
require 'shellwords'
require 'tmpdir'
require 'fileutils'
require 'optparse'

class MigrateYumToArchive
  include CiWorkflowSupport
  include ShellScriptingSupport
  include PublishingSupport

  def main
    parse_options
    require_envvar 'PRODUCTION_REPO_BUCKET_NAME'
    require_envvar 'ARCHIVE_REPO_BUCKET_NAME'

    print_header 'Initializing'
    load_config
    create_temp_dirs
    fetch_and_import_signing_key

    print_header 'Downloading main repository'
    version = get_latest_production_repo_version
    if version == 0
      abort 'ERROR: No production repository exists yet'
    end
    fetch_main_repo(version)

    print_header 'Identifying EOL distributions'
    eol_distros = identify_eol_distros
    if eol_distros.empty?
      log_notice 'No EOL distributions found to archive'
      exit
    end
    log_notice "EOL distributions to archive: #{eol_distros.join(', ')}"

    print_header 'Fetching existing archive (if any)'
    @archive_version = get_latest_archive_version
    if @archive_version > 0
      log_notice "Existing archive at version #{@archive_version}, will merge"
      fetch_archive_repo(@archive_version)
    else
      log_notice 'No existing archive — creating fresh'
      @archive_repo_path = "#{@temp_dir}/archive-repo"
      Dir.mkdir(@archive_repo_path)
    end

    if @dry_run
      log_notice 'DRY RUN — not uploading changes'
      print_summary(eol_distros, version)
      exit
    end

    print_header 'Uploading EOL distros to archive'
    upload_archive(eol_distros)

    print_header 'Removing EOL distros from main repository'
    remove_from_main(eol_distros, version)

    print_header 'Success!'
    print_summary(eol_distros, version)

    cleanup
  end

private
  def parse_options
    @dry_run = false
    @explicit_distros = nil

    OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options]"
      opts.on('--dry-run', 'Do not upload changes') { @dry_run = true }
      opts.on('--distros DISTROS', 'Comma-separated list of distros to archive') do |v|
        @explicit_distros = v.split(',').map(&:strip)
      end
    end.parse!
  end

  def create_temp_dirs
    @temp_dir = Dir.mktmpdir('yum-archive-migration')
    @local_repo_path = "#{@temp_dir}/repo"
    @signing_key_path = "#{@temp_dir}/key.gpg"
    Dir.mkdir(@local_repo_path)
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

  def get_latest_archive_version
    url = "gs://#{ENV['ARCHIVE_REPO_BUCKET_NAME']}/versions/latest_version.txt"
    stdout_output, stderr_output, status = run_command_capture_output(
      'gsutil', 'cp', url, '-',
      log_invocation: false,
      check_error: false
    )
    if status.success?
      v = stdout_output.strip
      if v =~ /\A[0-9]+\Z/
        v.to_i
      else
        abort("ERROR: invalid version number stored in #{url}")
      end
    elsif stderr_output =~ /No URLs matched/
      0
    else
      abort("ERROR: error fetching #{url}: #{stderr_output.chomp}")
    end
  end

  def fetch_archive_repo(version)
    @archive_repo_path = "#{@temp_dir}/archive-repo"
    Dir.mkdir(@archive_repo_path)
    log_notice "Fetching archive repo version #{version}"
    run_command(
      'gsutil', '-m', 'rsync', '-r',
      "gs://#{ENV['ARCHIVE_REPO_BUCKET_NAME']}/versions/#{version}/public",
      @archive_repo_path,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def fetch_main_repo(version)
    log_notice "Fetching main repo version #{version}"
    run_command(
      'gsutil', '-m', 'rsync', '-r',
      "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/#{version}/public",
      @local_repo_path,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def identify_eol_distros
    if @explicit_distros
      log_notice "Using explicitly specified distros: #{@explicit_distros.join(', ')}"
      return @explicit_distros
    end

    # List distro directories in the downloaded repo
    published = Dir.entries(@local_repo_path)
      .select { |e| File.directory?("#{@local_repo_path}/#{e}") }
      .reject { |e| e.start_with?('.') }

    supported = distributions
      .select { |d| d[:package_format] == :RPM }
      .map { |d| d[:name] }

    eol = published - supported
    log_info "Published distros in YUM repo: #{published.join(', ')}"
    log_info "Currently supported RPM distros: #{supported.join(', ')}"
    log_info "EOL distros (published but not supported): #{eol.join(', ')}"
    eol.sort
  end

  def upload_archive(eol_distros)
    archive_bucket = ENV['ARCHIVE_REPO_BUCKET_NAME']
    new_archive_version = @archive_version + 1

    # Copy EOL distro directories into the local archive repo
    eol_distros.each do |distro|
      src = "#{@local_repo_path}/#{distro}"
      dst = "#{@archive_repo_path}/#{distro}"
      log_notice "[#{distro}] Copying to archive staging area"
      FileUtils.cp_r(src, dst)
    end

    # Upload merged archive repo
    log_notice "Uploading archive repo as version #{new_archive_version}"
    run_command(
      'gsutil', '-m',
      '-h', 'Cache-Control:public',
      'rsync', '-r', '-d',
      @archive_repo_path,
      "gs://#{archive_bucket}/versions/#{new_archive_version}/public",
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )

    # Create version note
    run_bash(
      sprintf(
        'gsutil -q -h Content-Type:text/plain -h Cache-Control:no-store cp - %s <<<%s',
        Shellwords.escape("gs://#{archive_bucket}/versions/#{new_archive_version}/version.txt"),
        Shellwords.escape(new_archive_version.to_s)
      ),
      log_invocation: true,
      check_error: true,
      pipefail: false
    )

    # Declare latest version
    run_bash(
      sprintf(
        'gsutil -q -h Content-Type:text/plain -h Cache-Control:no-store cp - %s <<<%s',
        Shellwords.escape("gs://#{archive_bucket}/versions/latest_version.txt"),
        Shellwords.escape(new_archive_version.to_s)
      ),
      log_invocation: true,
      check_error: true,
      pipefail: false
    )
  end

  def remove_from_main(eol_distros, old_version)
    new_version = old_version + 1
    bucket = ENV['PRODUCTION_REPO_BUCKET_NAME']

    # Remove EOL distro directories from local copy
    eol_distros.each do |distro|
      distro_path = "#{@local_repo_path}/#{distro}"
      if File.exist?(distro_path)
        log_notice "[#{distro}] Removing from local repo"
        FileUtils.rm_rf(distro_path)
      end
    end

    # Upload trimmed repo as new version
    log_notice "Copying repo version #{old_version} to #{new_version}"
    run_command(
      'gsutil', '-m',
      '-h', 'Cache-Control:public',
      'rsync', '-r', '-d',
      "gs://#{bucket}/versions/#{old_version}/public",
      "gs://#{bucket}/versions/#{new_version}/public",
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )

    log_notice "Uploading trimmed repo as version #{new_version}"
    run_command(
      'gsutil', '-m',
      '-h', 'Cache-Control:public',
      'rsync', '-r', '-d',
      @local_repo_path,
      "gs://#{bucket}/versions/#{new_version}/public",
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )

    # Version note
    run_bash(
      sprintf(
        'gsutil -q -h Content-Type:text/plain -h Cache-Control:public cp - %s <<<%s',
        Shellwords.escape("gs://#{bucket}/versions/#{new_version}/version.txt"),
        Shellwords.escape(new_version.to_s)
      ),
      log_invocation: true,
      check_error: true,
      pipefail: false
    )

    # Activate
    log_notice "Activating main repo version #{new_version}"
    run_bash(
      sprintf(
        'gsutil -q -h Content-Type:text/plain -h Cache-Control:no-store cp - %s <<<%s',
        Shellwords.escape("gs://#{bucket}/versions/latest_version.txt"),
        Shellwords.escape(new_version.to_s)
      ),
      log_invocation: true,
      check_error: true,
      pipefail: false
    )
  end

  def print_summary(eol_distros, old_version)
    new_archive_version = @archive_version + 1
    archive_bucket = ENV['ARCHIVE_REPO_BUCKET_NAME']
    log_notice 'Migration summary'
    log_info "Archived distributions: #{eol_distros.join(', ')}"
    log_info "Main repo: version #{old_version} -> #{old_version + 1}"
    log_info "Archive repo: version #{@archive_version} -> #{new_archive_version}"
    log_info ''
    log_info 'Archive YUM repo URL:'
    log_info "  https://storage.googleapis.com/#{archive_bucket}/versions/#{new_archive_version}/public"
    log_info ''
    log_info 'Next steps:'
    log_info '  1. Restart the web server to pick up new archive version'
    log_info '  2. Verify archive repo: curl https://yum-archive.fullstaqruby.org/'
    log_info '  3. Verify main repo still works on a supported distro'
  end

  def cleanup
    log_info "Cleaning up #{@temp_dir}"
    FileUtils.remove_entry_secure(@temp_dir)
  end
end

MigrateYumToArchive.new.main
