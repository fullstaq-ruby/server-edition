#!/usr/bin/env ruby
# frozen_string_literal: true

# Moves packages that no longer belong in the live YUM repository into the
# archive YUM repository. A package leaves the live repository when its
# distribution, or its Ruby minor version, is no longer listed in config.yml.
# The live and archive repositories never contain the same package.
#
# Usage:
#   PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-yum-repo \
#   ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-yum-archive-repo \
#   ./internal-scripts/ci-cd/archive/archive-yum-packages.rb [--dry-run]
#
# Safe to rerun: RPMs already in the archive are skipped, and the live
# repository is only modified after the archive has been uploaded and
# activated.
#
# See dev-handbook/archiving-eol-packages.md.

require_relative '../../../lib/gcloud_storage_lock'
require_relative '../../../lib/ci_workflow_support'
require_relative '../../../lib/general_support'
require_relative '../../../lib/shell_scripting_support'
require_relative '../../../lib/publishing_support'
require 'shellwords'
require 'tmpdir'
require 'fileutils'
require 'optparse'
require 'zlib'

class ArchiveYumPackages
  # Matches: fullstaq-ruby-3.1-rev5-el9.x86_64.rpm, fullstaq-ruby-3.1-jemalloc-..., fullstaq-ruby-3.1.7-...
  # Does NOT match: fullstaq-ruby-common-*, fullstaq-rbenv-*
  RUBY_RPM_PATTERN = /\Afullstaq-ruby-(\d+\.\d+)/

  include CiWorkflowSupport
  include GeneralSupport
  include ShellScriptingSupport
  include PublishingSupport

  def main
    parse_options
    require_envvar 'PRODUCTION_REPO_BUCKET_NAME'
    require_envvar 'ARCHIVE_REPO_BUCKET_NAME'

    print_header 'Initializing'
    load_config
    create_temp_dirs
    begin
      pull_utility_image_if_not_exists
      initialize_locking
      fetch_and_import_signing_key

      synchronize do
        print_header 'Fetching live repository'
        @live_version = get_latest_version(live_bucket)
        abort 'ERROR: No production repository exists yet' if @live_version == 0
        fetch_repo(live_bucket, @live_version, @live_repo_path)

        print_header 'Determining packages to archive'
        @moves = determine_moves
        if @moves.empty?
          log_notice 'Nothing to archive'
          return
        end
        print_moves

        print_header 'Fetching archive repository'
        @archive_version = get_latest_version(archive_bucket)
        if @archive_version > 0
          fetch_repo(archive_bucket, @archive_version, @archive_repo_path)
        else
          log_notice 'No archive exists yet, creating a new one'
        end

        print_header 'Adding packages to archive repository'
        add_to_archive
        verify_archive
        check_lock_health

        print_header 'Removing packages from live repository'
        remove_from_live
        verify_live
        check_lock_health

        if @dry_run
          log_notice 'Dry run: not uploading changes'
          return
        end

        # The archive must be complete and activated before the live
        # repository stops serving these packages.
        print_header 'Uploading archive repository'
        upload_version(archive_bucket, @archive_version, @archive_repo_path)

        print_header 'Uploading live repository'
        upload_version(live_bucket, @live_version, @live_repo_path)

        print_header 'Success!'
        print_summary
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
      opts.on('--dry-run', 'Make all changes locally, but do not upload them') { @dry_run = true }
    end.parse!
  end

  def live_bucket
    ENV['PRODUCTION_REPO_BUCKET_NAME']
  end

  def archive_bucket
    ENV['ARCHIVE_REPO_BUCKET_NAME']
  end

  def create_temp_dirs
    log_notice 'Creating temporary directories'
    # Under /tmp, not $TMPDIR: on macOS $TMPDIR is too long for gpg-agent's
    # socket path, and the GPG home directory lives here.
    @temp_dir = Dir.mktmpdir('archive-yum', '/tmp')
    @signing_key_path = "#{@temp_dir}/key.gpg"
    @live_repo_path = "#{@temp_dir}/live-repo"
    @archive_repo_path = "#{@temp_dir}/archive-repo"
    Dir.mkdir(@live_repo_path)
    Dir.mkdir(@archive_repo_path)
  end

  def initialize_locking
    # The archive bucket has no lock of its own. It is only ever written
    # while holding the live repository's lock.
    @lock = GCloudStorageLock.new(url: "gs://#{live_bucket}/locks/yum")
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
    log_info "Signing key ID: #{@gpg_key_id}"
    import_gpg_key(@temp_dir, @signing_key_path)
  end

  def get_latest_version(bucket)
    url = "gs://#{bucket}/versions/latest_version.txt"
    stdout_output, stderr_output, status = run_command_capture_output(
      'gsutil', 'cp', url, '-',
      log_invocation: false,
      check_error: false
    )
    if status.success?
      version = stdout_output.strip
      abort("ERROR: invalid version number stored in #{url}") if version !~ /\A[0-9]+\Z/
      version = version.to_i
    elsif stderr_output =~ /No URLs matched/
      version = 0
    else
      abort("ERROR: error fetching #{url}: #{stderr_output.chomp}")
    end
    log_notice "Latest version of #{bucket}: #{version}"
    version
  end

  def fetch_repo(bucket, version, repo_path)
    log_notice "Fetching #{bucket} version #{version}"
    run_command(
      'gsutil', '-m', 'rsync', '-r',
      "gs://#{bucket}/versions/#{version}/public",
      repo_path,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def supported_distros
    distributions.find_all { |d| d[:package_format] == :RPM }.map { |d| d[:name] }
  end

  # A minor version is active while CI still builds any package for it:
  # its minor-version package, or one of its tiny-version packages.
  # Archiving a package CI still builds would put it in both repositories.
  def active_ruby_minor_versions
    minors = (config[:ruby][:minor_version_packages] || []).map { |p| p[:minor_version] }
    tinys = (config[:ruby][:tiny_version_packages] || []).map { |p| p[:full_version].split('.')[0..1].join('.') }
    (minors + tinys).uniq
  end

  def eol_ruby_rpm?(filename, active_minors)
    filename =~ RUBY_RPM_PATTERN && !active_minors.include?($1)
  end

  def distro_dirs(repo_path)
    Dir["#{repo_path}/*"].find_all { |path| File.directory?(path) }.map { |path| File.basename(path) }.sort
  end

  def arch_dirs(repo_path, distro)
    Dir["#{repo_path}/#{distro}/*"].find_all { |path| File.directory?(path) }.map { |path| File.basename(path) }.sort
  end

  # Returns a hash: distro => { whole_distro: Boolean, rpms: { arch => [filenames] } }
  def determine_moves
    supported = supported_distros
    active_minors = active_ruby_minor_versions
    log_info "Supported RPM distributions: #{supported.join(', ')}"
    log_info "Active Ruby minor versions: #{active_minors.join(', ')}"

    moves = {}
    distro_dirs(@live_repo_path).each do |distro|
      whole_distro = !supported.include?(distro)
      rpms = {}
      arch_dirs(@live_repo_path, distro).each do |arch|
        filenames = Dir["#{@live_repo_path}/#{distro}/#{arch}/*.rpm"].map { |path| File.basename(path) }.sort
        filenames = filenames.find_all { |filename| eol_ruby_rpm?(filename, active_minors) } if !whole_distro
        rpms[arch] = filenames if !filenames.empty?
      end
      moves[distro] = { whole_distro: whole_distro, rpms: rpms } if whole_distro || !rpms.empty?
    end
    moves
  end

  def print_moves
    @moves.each_pair do |distro, move|
      reason = move[:whole_distro] ? 'EOL distribution' : 'EOL Ruby versions'
      count = move[:rpms].values.sum(&:size)
      log_notice "[#{distro}] #{count} packages to archive (#{reason})"
      move[:rpms].each_pair do |arch, filenames|
        filenames.each { |filename| log_info "  #{YELLOW}ARCHIVE#{RESET} #{arch}/#{filename}" }
      end
    end
  end

  def add_to_archive
    @moves.each_pair do |distro, move|
      move[:rpms].each_pair do |arch, filenames|
        target_dir = "#{@archive_repo_path}/#{distro}/#{arch}"
        FileUtils.mkdir_p(target_dir)
        copied = 0
        filenames.each do |filename|
          target_path = "#{target_dir}/#{filename}"
          next if File.exist?(target_path)
          hardlink_or_copy_file("#{@live_repo_path}/#{distro}/#{arch}/#{filename}", target_path)
          copied += 1
        end
        log_notice "[#{distro}/#{arch}] Copied #{copied} packages to archive (#{filenames.size - copied} already present)"
        regenerate_repo_metadata(target_dir)
      end
    end
  end

  def verify_archive
    log_notice 'Verifying archive repository'
    @moves.each_pair do |distro, move|
      move[:rpms].each_pair do |arch, filenames|
        dir = "#{@archive_repo_path}/#{distro}/#{arch}"
        missing = filenames - indexed_rpms(dir)
        if !missing.empty?
          abort("ERROR: [#{distro}/#{arch}] packages missing from archive metadata: #{missing.join(', ')}")
        end
        log_info "[#{distro}/#{arch}] All #{filenames.size} packages present in archive"
      end
    end
  end

  def remove_from_live
    @moves.each_pair do |distro, move|
      if move[:whole_distro]
        log_notice "[#{distro}] Removing distribution from live repository"
        FileUtils.rm_rf("#{@live_repo_path}/#{distro}")
      else
        move[:rpms].each_pair do |arch, filenames|
          dir = "#{@live_repo_path}/#{distro}/#{arch}"
          log_notice "[#{distro}/#{arch}] Removing #{filenames.size} packages from live repository"
          filenames.each { |filename| File.delete("#{dir}/#{filename}") }
          regenerate_repo_metadata(dir)
        end
      end
    end
  end

  def verify_live
    log_notice 'Verifying live repository'
    @moves.each_pair do |distro, move|
      if move[:whole_distro]
        abort("ERROR: [#{distro}] still present in live repository") if File.exist?("#{@live_repo_path}/#{distro}")
      else
        move[:rpms].each_pair do |arch, filenames|
          dir = "#{@live_repo_path}/#{distro}/#{arch}"
          leftover = filenames & (indexed_rpms(dir) + Dir["#{dir}/*.rpm"].map { |path| File.basename(path) })
          if !leftover.empty?
            abort("ERROR: [#{distro}/#{arch}] packages still in live repository: #{leftover.join(', ')}")
          end
        end
      end
    end
  end

  # RPM filenames listed in a directory's repodata. This is what YUM clients actually see.
  def indexed_rpms(dir)
    primary = Dir["#{dir}/repodata/*-primary.xml.gz"]
    return [] if primary.empty?
    abort("ERROR: multiple primary.xml.gz files in #{dir}/repodata") if primary.size > 1
    xml = Zlib::GzipReader.open(primary[0], &:read)
    xml.scan(/<location href="([^"]+)"/).map { |(href)| File.basename(href) }
  end

  def regenerate_repo_metadata(dir)
    invoke_createrepo(dir)
    sign_repo(dir)
  end

  def invoke_createrepo(dir)
    update_arg = File.exist?("#{dir}/repodata/repomd.xml") ? ['--update'] : []
    run_command(
      'docker', 'run', '--rm',
      '-v', "#{dir}:/input:delegated",
      '--user', "#{Process.uid}:#{Process.gid}",
      utility_image_name,
      'createrepo_c',
      *update_arg,
      '/input',
      log_invocation: true,
      check_error: true
    )
  end

  def sign_repo(dir)
    run_command(
      'gpg', "--homedir=#{@temp_dir}", "--local-user=#{@gpg_key_id}",
      '--batch', '--yes', '--detach-sign', '--armor',
      "#{dir}/repodata/repomd.xml",
      log_invocation: true,
      check_error: true
    )
  end

  def upload_version(bucket, old_version, repo_path)
    new_version = old_version + 1
    version_url = "gs://#{bucket}/versions/#{new_version}"
    log_notice "Uploading #{bucket} version #{new_version}"

    if old_version > 0
      # Server-side copy first, so that the upload below only transfers changes.
      run_command(
        'gsutil', '-m', '-h', 'Cache-Control:public',
        'rsync', '-r', '-d',
        "gs://#{bucket}/versions/#{old_version}/public",
        "#{version_url}/public",
        log_invocation: true,
        check_error: true,
        passthru_output: true
      )
    end

    run_command(
      'gsutil', '-m', '-h', 'Cache-Control:public',
      'rsync', '-r', '-d',
      repo_path,
      "#{version_url}/public",
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )

    write_gcs_text("#{version_url}/version.txt", new_version, 'public')
    check_lock_health
    log_notice "Activating #{bucket} version #{new_version}"
    write_gcs_text("gs://#{bucket}/versions/latest_version.txt", new_version, 'no-store')
  end

  def write_gcs_text(url, content, cache_control)
    run_bash(
      sprintf('gsutil -q -h Content-Type:text/plain -h Cache-Control:%s cp - %s <<<%s',
        cache_control,
        Shellwords.escape(url),
        Shellwords.escape(content.to_s)),
      log_invocation: true,
      check_error: true,
      pipefail: false
    )
  end

  def print_summary
    log_notice 'Summary'
    @moves.each_pair do |distro, move|
      suffix = move[:whole_distro] ? ' (distribution removed from live)' : ''
      log_info "#{distro}: archived #{move[:rpms].values.sum(&:size)} packages#{suffix}"
    end
    log_info "Live repository: version #{@live_version} -> #{@live_version + 1}"
    log_info "Archive repository: version #{@archive_version} -> #{@archive_version + 1}"
    log_info ''
    log_info 'Next steps:'
    log_info '  1. Restart Caddy on the backend server: sudo systemctl restart caddy'
    log_info '     Until then, yum.fullstaqruby.org and yum-archive.fullstaqruby.org serve the old versions.'
    log_info '  2. Verify: curl -fsS https://yum-archive.fullstaqruby.org/<distro>/<arch>/repodata/repomd.xml'
  end

  def cleanup
    return if @temp_dir.nil?
    log_info "Cleaning up #{@temp_dir}"
    FileUtils.remove_entry_secure(@temp_dir)
  end
end

ArchiveYumPackages.new.main
