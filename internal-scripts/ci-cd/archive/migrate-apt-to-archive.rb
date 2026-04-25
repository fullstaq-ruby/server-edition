#!/usr/bin/env ruby
# frozen_string_literal: true

# Incremental migration script to move EOL distribution packages
# from the main APT repository to the archive APT repository.
# Safe to run repeatedly — merges new EOL distros into the existing archive.
#
# Usage:
#   PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
#   ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo-archive \
#   ./internal-scripts/ci-cd/archive/migrate-apt-to-archive.rb [--dry-run] [--distros centos-8,debian-9]
#
# If --distros is not specified, automatically detects EOL distros by comparing
# the Aptly state against the current environments/ directory.

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

class MigrateAptToArchive
  REPO_ORIGIN = 'Fullstaq-Ruby'
  REPO_LABEL = 'Fullstaq-Ruby'

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
    ensure_gpg_state_isolated
    activate_wrappers_bin_dir
    initialize_aptly(@main_aptly_config_path, @main_state_path, @main_state_repo_path)
    fetch_and_import_signing_key

    print_header 'Downloading main repository state'
    version = get_latest_production_repo_version
    if version == 0
      abort 'ERROR: No production repository exists yet'
    end
    fetch_main_state(version)

    print_header 'Identifying EOL distributions'
    eol_distros = identify_eol_distros
    if eol_distros.empty?
      log_notice 'No EOL distributions found to archive'
      exit
    end
    log_notice "EOL distributions to archive: #{eol_distros.join(', ')}"

    print_header 'Fetching existing archive state (if any)'
    @archive_version = get_latest_archive_version
    if @archive_version > 0
      log_notice "Existing archive at version #{@archive_version}, will merge"
      fetch_archive_state(@archive_version)
    else
      log_notice 'No existing archive — creating fresh'
    end

    print_header 'Creating archive repository'
    create_archive_state(eol_distros)

    print_header 'Trimming main repository state'
    trim_main_state(eol_distros)

    if @dry_run
      log_notice 'DRY RUN — not uploading changes'
      print_summary(eol_distros, version)
      exit
    end

    print_header 'Uploading archive repository'
    upload_archive

    print_header 'Uploading trimmed main repository'
    upload_main(version)

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
    log_notice 'Creating temporary directories'
    @temp_dir = Dir.mktmpdir('apt-archive-migration')
    @wrappers_bin_dir = "#{@temp_dir}/wrappers"

    @main_aptly_config_path = "#{@temp_dir}/aptly-main.conf"
    @main_state_path = "#{@temp_dir}/main-state"
    @main_state_db_path = "#{@main_state_path}/db"
    @main_state_repo_path = "#{@main_state_path}/repo"
    @main_state_archive_path = "#{@temp_dir}/main-state.tar.zst"

    @archive_aptly_config_path = "#{@temp_dir}/aptly-archive.conf"
    @archive_state_path = "#{@temp_dir}/archive-state"
    @archive_state_db_path = "#{@archive_state_path}/db"
    @archive_state_repo_path = "#{@archive_state_path}/repo"
    @archive_state_archive_path = "#{@temp_dir}/archive-state.tar.zst"

    @signing_key_path = "#{@temp_dir}/key.gpg"

    Dir.mkdir(@wrappers_bin_dir)
    [@main_state_path, @main_state_db_path, @main_state_repo_path,
     @archive_state_path, @archive_state_db_path, @archive_state_repo_path].each do |dir|
      FileUtils.mkdir_p(dir)
    end
  end

  def ensure_gpg_state_isolated
    log_notice 'Creating GPG wrapper'
    File.open("#{@wrappers_bin_dir}/gpg", 'w:utf-8') do |f|
      f.write("#!/bin/sh\n")
      f.write(
        sprintf(
          "exec %s --homedir %s \"$@\"\n",
          Shellwords.escape(find_gpg),
          Shellwords.escape(@temp_dir)
        )
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

  def initialize_aptly(config_path, state_path, repo_path)
    log_notice "Creating Aptly config: #{config_path}"
    File.open(config_path, 'w:utf-8') do |f|
      f.write(JSON.generate(
        rootDir: state_path,
        FileSystemPublishEndpoints: {
          main: {
            rootDir: repo_path,
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

  def fetch_main_state(version)
    log_notice "Fetching main state version #{version}"
    url = "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/#{version}/state.tar.zst"
    run_bash(
      sprintf('gsutil -m cp %s - | zstd -dc | tar -xC %s',
        Shellwords.escape(url),
        Shellwords.escape(@main_state_path)),
      pipefail: true,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
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

  def fetch_archive_state(version)
    log_notice "Fetching archive state version #{version}"
    url = "gs://#{ENV['ARCHIVE_REPO_BUCKET_NAME']}/versions/#{version}/state.tar.zst"
    run_bash(
      sprintf('gsutil -m cp %s - | zstd -dc | tar -xC %s',
        Shellwords.escape(url),
        Shellwords.escape(@archive_state_path)),
      pipefail: true,
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

    published = list_aptly_repos(@main_aptly_config_path)
    supported = distributions
      .select { |d| d[:package_format] == :DEB }
      .map { |d| d[:name] }

    eol = published - supported
    log_info "Published distros in Aptly state: #{published.join(', ')}"
    log_info "Currently supported DEB distros: #{supported.join(', ')}"
    log_info "EOL distros (published but not supported): #{eol.join(', ')}"
    eol.sort
  end

  def list_aptly_repos(config_path)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'repo', 'list',
      "-config=#{config_path}",
      '-raw',
      log_invocation: true,
      check_error: true
    )
    stdout_output.split("\n").map(&:strip).reject(&:empty?)
  end

  def list_aptly_packages(config_path, repo_name)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'repo', 'show',
      "-config=#{config_path}",
      '-with-packages',
      repo_name,
      log_invocation: false,
      check_error: true
    )
    stdout_output.sub!(/.*^Packages:$/m, '')
    stdout_output.split("\n").map(&:strip).reject(&:empty?)
  end

  def create_archive_state(eol_distros)
    if @archive_version == 0
      initialize_aptly(@archive_aptly_config_path, @archive_state_path, @archive_state_repo_path)
    else
      # Existing archive was fetched — just initialize the Aptly config pointing at it
      initialize_aptly(@archive_aptly_config_path, @archive_state_path, @archive_state_repo_path)
      existing = list_aptly_repos(@archive_aptly_config_path)
      log_notice "Existing archive contains distros: #{existing.join(', ')}"
    end

    # Copy EOL packages from main pool into archive pool
    main_pool = "#{@main_state_path}/pool"
    archive_pool = "#{@archive_state_path}/pool"
    if File.exist?(main_pool)
      if File.exist?(archive_pool)
        # Merge: copy new pool files that don't already exist
        run_bash(
          sprintf('cp -rn %s/* %s/ 2>/dev/null || true',
            Shellwords.escape(main_pool),
            Shellwords.escape(archive_pool)),
          log_invocation: false, check_error: false, pipefail: false
        )
      else
        FileUtils.cp_r(main_pool, @archive_state_path)
      end
    end

    eol_distros.each do |distro|
      packages = list_aptly_packages(@main_aptly_config_path, distro)
      log_notice "[#{distro}] Exporting #{packages.size} packages to archive"

      # Create the archive repo for this distro
      run_command(
        'aptly', 'repo', 'create',
        "-config=#{@archive_aptly_config_path}",
        distro,
        log_invocation: true,
        check_error: true
      )

      # Import packages by copying the Aptly database directory for this repo
      main_repo_db = "#{@main_state_db_path}/repo/#{distro}"
      if File.exist?(main_repo_db)
        FileUtils.cp_r(main_repo_db, "#{@archive_state_db_path}/repo/")
      end
    end

    # Publish all distros in the archive (existing + newly added)
    all_archive_distros = list_aptly_repos(@archive_aptly_config_path)
    all_archive_distros.each do |distro|
      log_notice "[#{distro}] Publishing in archive"
      publish_aptly_repo(@archive_aptly_config_path, distro)
    end

    # Archive the state
    log_notice 'Creating archive state archive'
    run_bash(
      sprintf("tar -C %s -cf - . | zstd -T0 > %s",
        Shellwords.escape(@archive_state_path),
        Shellwords.escape(@archive_state_archive_path)),
      pipefail: true,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def trim_main_state(eol_distros)
    eol_distros.each do |distro|
      log_notice "[#{distro}] Dropping from main repository"

      # Drop the publication first (if it exists)
      run_command(
        'aptly', 'publish', 'drop',
        "-config=#{@main_aptly_config_path}",
        distro, 'filesystem:main:.',
        log_invocation: true,
        check_error: false
      )

      # Drop the repo
      run_command(
        'aptly', 'repo', 'drop',
        "-config=#{@main_aptly_config_path}",
        distro,
        log_invocation: true,
        check_error: true
      )
    end

    # Compact the database to reclaim space from dropped packages
    log_notice 'Compacting main state'
    run_command(
      'aptly', 'db', 'cleanup',
      "-config=#{@main_aptly_config_path}",
      '-verbose',
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )

    # Re-publish remaining distros
    remaining = list_aptly_repos(@main_aptly_config_path)
    remaining.each do |distro|
      log_notice "[#{distro}] Re-publishing in main repository"
      publish_aptly_repo(@main_aptly_config_path, distro)
    end

    # Re-archive the trimmed state
    log_notice 'Creating trimmed main state archive'
    run_bash(
      sprintf("tar -C %s -cf - . | zstd -T0 > %s",
        Shellwords.escape(@main_state_path),
        Shellwords.escape(@main_state_archive_path)),
      pipefail: true,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def publish_aptly_repo(config_path, distro)
    _, stderr_output, status = run_command_capture_output(
      'aptly', 'publish', 'repo',
      '-batch', '-force-overwrite',
      "-config=#{config_path}",
      "-gpg-key=#{@gpg_key_id}",
      "-distribution=#{distro}",
      "-origin=#{REPO_ORIGIN}",
      "-label=#{REPO_LABEL}",
      distro, 'filesystem:main:.',
      log_invocation: true,
      check_error: false
    )
    if !status.success?
      if stderr_output =~ /unable to figure out list of architectures/
        run_command(
          'aptly', 'publish', 'repo',
          '-batch', '-force-overwrite', '-architectures=all',
          "-config=#{config_path}",
          "-gpg-key=#{@gpg_key_id}",
          "-distribution=#{distro}",
          "-origin=#{REPO_ORIGIN}",
          "-label=#{REPO_LABEL}",
          distro, 'filesystem:main:.',
          log_invocation: true,
          check_error: true
        )
      else
        abort("ERROR publishing #{distro}: #{stderr_output.chomp}")
      end
    end
  end

  def upload_archive
    archive_bucket = ENV['ARCHIVE_REPO_BUCKET_NAME']
    new_archive_version = @archive_version + 1

    # Upload state
    log_notice "Uploading archive state as version #{new_archive_version}"
    run_command(
      'gsutil',
      '-h', 'Cache-Control:public',
      'cp',
      @archive_state_archive_path,
      "gs://#{archive_bucket}/versions/#{new_archive_version}/state.tar.zst",
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )

    # Upload published repo
    log_notice 'Uploading archive repository'
    run_command(
      'gsutil', '-m',
      '-h', 'Cache-Control:public',
      'rsync', '-r', '-d',
      @archive_state_repo_path,
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

  def upload_main(old_version)
    new_version = old_version + 1
    bucket = ENV['PRODUCTION_REPO_BUCKET_NAME']

    # Upload state
    log_notice "Uploading trimmed main state as version #{new_version}"
    run_command(
      'gsutil',
      '-h', 'Cache-Control:public',
      'cp',
      @main_state_archive_path,
      "gs://#{bucket}/versions/#{new_version}/state.tar.zst",
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )

    # Copy previous repo version, then overwrite with trimmed version
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
      @main_state_repo_path,
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

    # Activate new version
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
    log_info 'Archive APT repo URL:'
    log_info "  https://storage.googleapis.com/#{archive_bucket}/versions/#{new_archive_version}/public"
    log_info ''
    log_info 'Next steps:'
    log_info '  1. Restart the web server to pick up new archive version'
    log_info '  2. Verify archive repo: curl https://apt-archive.fullstaqruby.org/dists/'
    log_info '  3. Verify main repo still works: apt-get update on a supported distro'
  end

  def cleanup
    log_info "Cleaning up #{@temp_dir}"
    FileUtils.remove_entry_secure(@temp_dir)
  end
end

MigrateAptToArchive.new.main
