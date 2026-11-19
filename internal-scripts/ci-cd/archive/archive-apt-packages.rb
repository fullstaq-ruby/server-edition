#!/usr/bin/env ruby
# frozen_string_literal: true

# Moves packages that no longer belong in the live APT repository into the
# archive APT repository. A package leaves the live repository when its
# distribution, or its Ruby minor version, is no longer listed in config.yml.
# The live and archive repositories never contain the same package.
#
# Usage:
#   PRODUCTION_REPO_BUCKET_NAME=fsruby-server-edition-apt-repo \
#   ARCHIVE_REPO_BUCKET_NAME=fsruby-server-edition-apt-archive-repo \
#   ./internal-scripts/ci-cd/archive/archive-apt-packages.rb [--dry-run]
#
# Safe to rerun: packages already in the archive are re-added as a no-op,
# and the live repository is only modified after the archive has been
# uploaded and activated.
#
# See dev-handbook/archiving-eol-packages.md.

require_relative '../../../lib/gcloud_storage_lock'
require_relative '../../../lib/ci_workflow_support'
require_relative '../../../lib/shell_scripting_support'
require_relative '../../../lib/publishing_support'
require 'json'
require 'shellwords'
require 'tmpdir'
require 'fileutils'
require 'optparse'

class ArchiveAptPackages
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
    require_envvar 'ARCHIVE_REPO_BUCKET_NAME'

    print_header 'Initializing'
    load_config
    create_temp_dirs
    begin
      ensure_gpg_state_isolated
      activate_wrappers_bin_dir
      initialize_locking
      initialize_aptly(@live_aptly_config_path, @live_state_path)
      initialize_aptly(@archive_aptly_config_path, @archive_state_path)
      fetch_and_import_signing_key

      synchronize do
        print_header 'Fetching live repository state'
        @live_version = get_latest_version(live_bucket)
        abort 'ERROR: No production repository exists yet' if @live_version == 0
        fetch_state(live_bucket, @live_version, @live_state_path)

        print_header 'Determining packages to archive'
        @moves = determine_moves
        if @moves.empty?
          log_notice 'Nothing to archive'
          return
        end
        print_moves

        print_header 'Fetching archive repository state'
        @archive_version = get_latest_version(archive_bucket)
        if @archive_version > 0
          fetch_state(archive_bucket, @archive_version, @archive_state_path)
        else
          log_notice 'No archive exists yet, creating a new one'
        end

        print_header 'Moving packages'
        add_to_archive
        remove_from_live
        compact_aptly_db(@archive_aptly_config_path)
        compact_aptly_db(@live_aptly_config_path)

        # Like publish-debs.rb, the state is archived *before* publishing,
        # so that it contains no publications and an empty repo/ directory.
        # publish-debs.rb creates publications without dropping them first,
        # which fails if the state already has one.
        if !@dry_run
          print_header 'Creating state archives'
          create_state_tarball(@archive_state_path, @archive_state_tarball_path)
          create_state_tarball(@live_state_path, @live_state_tarball_path)
        end
        check_lock_health

        # Every distribution is published, not only the ones that changed:
        # the upload replaces the entire public tree with repo/.
        print_header 'Publishing repositories'
        publish_all(@archive_aptly_config_path)
        publish_all(@live_aptly_config_path)
        verify_archive
        verify_live
        check_lock_health

        if @dry_run
          log_notice 'Dry run: not uploading changes'
          return
        end

        # The archive must be complete and activated before the live
        # repository stops serving these packages.
        print_header 'Uploading archive repository'
        upload_version(archive_bucket, @archive_version, @archive_state_path, @archive_state_tarball_path)

        print_header 'Uploading live repository'
        upload_version(live_bucket, @live_version, @live_state_path, @live_state_tarball_path)

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
    @temp_dir = Dir.mktmpdir('archive-apt', '/tmp')
    @wrappers_bin_dir = "#{@temp_dir}/wrappers"
    @signing_key_path = "#{@temp_dir}/key.gpg"

    @live_aptly_config_path = "#{@temp_dir}/aptly-live.conf"
    @live_state_path = "#{@temp_dir}/live-state"
    @live_state_tarball_path = "#{@temp_dir}/live-state.tar.zst"

    @archive_aptly_config_path = "#{@temp_dir}/aptly-archive.conf"
    @archive_state_path = "#{@temp_dir}/archive-state"
    @archive_state_tarball_path = "#{@temp_dir}/archive-state.tar.zst"

    Dir.mkdir(@wrappers_bin_dir)
    [@live_state_path, @archive_state_path].each do |state_path|
      FileUtils.mkdir_p("#{state_path}/db")
      FileUtils.mkdir_p("#{state_path}/repo")
    end
  end

  def ensure_gpg_state_isolated
    # Aptly invokes 'gpg' from PATH. We make that use an isolated
    # home directory, so that only the signing key is available.
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

  def initialize_locking
    # The archive bucket has no lock of its own. It is only ever written
    # while holding the live repository's lock.
    @lock = GCloudStorageLock.new(url: "gs://#{live_bucket}/locks/apt")
  end

  def synchronize(&block)
    @lock.synchronize(&block)
  end

  def check_lock_health
    abort 'ERROR: lock is unhealthy. Aborting operation' if !@lock.healthy?
  end

  def initialize_aptly(config_path, state_path)
    log_notice "Creating Aptly config file #{config_path}"
    File.open(config_path, 'w:utf-8') do |f|
      f.write(JSON.generate(
        rootDir: state_path,
        FileSystemPublishEndpoints: {
          main: {
            rootDir: "#{state_path}/repo",
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

  def fetch_state(bucket, version, state_path)
    log_notice "Fetching state of #{bucket} version #{version}"
    run_bash(
      sprintf('gsutil -m cp %s - | zstd -dc | tar -xC %s',
        Shellwords.escape("gs://#{bucket}/versions/#{version}/state.tar.zst"),
        Shellwords.escape(state_path)),
      pipefail: true,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def supported_distros
    distributions.find_all { |d| d[:package_format] == :DEB }.map { |d| d[:name] }
  end

  # A minor version is active while CI still builds any package for it:
  # its minor-version package, or one of its tiny-version packages.
  # Archiving a package CI still builds would put it in both repositories.
  def active_ruby_minor_versions
    minors = (config[:ruby][:minor_version_packages] || []).map { |p| p[:minor_version] }
    tinys = (config[:ruby][:tiny_version_packages] || []).map { |p| p[:full_version].split('.')[0..1].join('.') }
    (minors + tinys).uniq
  end

  def eol_ruby_package?(package_key, active_minors)
    package_key =~ RUBY_PACKAGE_PATTERN && !active_minors.include?($1)
  end

  # Returns a hash: distro => { whole_distro: Boolean, packages: [package keys] }
  def determine_moves
    supported = supported_distros
    active_minors = active_ruby_minor_versions
    log_info "Supported DEB distributions: #{supported.join(', ')}"
    log_info "Active Ruby minor versions: #{active_minors.join(', ')}"

    moves = {}
    list_aptly_repos(@live_aptly_config_path).each do |distro|
      packages = list_aptly_packages(@live_aptly_config_path, distro)
      if !supported.include?(distro)
        moves[distro] = { whole_distro: true, packages: packages }
      else
        eol_packages = packages.find_all { |key| eol_ruby_package?(key, active_minors) }
        moves[distro] = { whole_distro: false, packages: eol_packages } if !eol_packages.empty?
      end
    end
    moves
  end

  def print_moves
    @moves.each_pair do |distro, move|
      reason = move[:whole_distro] ? 'EOL distribution' : 'EOL Ruby versions'
      log_notice "[#{distro}] #{move[:packages].size} packages to archive (#{reason})"
      move[:packages].each { |key| log_info "  #{YELLOW}ARCHIVE#{RESET} #{key}" }
    end
  end

  def add_to_archive
    existing_repos = list_aptly_repos(@archive_aptly_config_path)

    @moves.each_pair do |distro, move|
      next if move[:packages].empty?

      log_notice "[#{distro}] Adding #{move[:packages].size} packages to archive"
      if !existing_repos.include?(distro)
        run_command(
          'aptly', 'repo', 'create',
          "-config=#{@archive_aptly_config_path}",
          distro,
          log_invocation: true,
          check_error: true
        )
      end

      move[:packages].each_slice(50) do |batch|
        # -force-replace makes re-adding a package that is already in
        # the archive a no-op, which is what makes reruns safe.
        run_command(
          'aptly', 'repo', 'add', '-force-replace',
          "-config=#{@archive_aptly_config_path}",
          distro,
          *live_pool_paths(batch),
          log_invocation: false,
          check_error: true
        )
      end
    end
  end

  # Paths of the .deb files in the live state's pool for the given package keys.
  def live_pool_paths(package_keys)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'package', 'show',
      "-config=#{@live_aptly_config_path}",
      '-with-files',
      package_keys.join(' | '),
      log_invocation: false,
      check_error: true
    )
    paths = stdout_output.scan(/^Files in the pool:\n((?:  .+\n?)+)/).flat_map do |(block)|
      block.split("\n").map(&:strip)
    end
    if paths.size != package_keys.size || !paths.all? { |path| File.exist?(path) }
      abort("ERROR: expected #{package_keys.size} pool files, found #{paths.size}: #{package_keys.join(', ')}")
    end
    paths
  end

  def verify_archive
    log_notice 'Verifying archive repository'
    @moves.each_pair do |distro, move|
      next if move[:packages].empty?

      archived = list_aptly_packages(@archive_aptly_config_path, distro)
      missing = move[:packages] - archived
      if !missing.empty?
        abort("ERROR: [#{distro}] packages missing from archive: #{missing.join(', ')}")
      end

      published = published_packages("#{@archive_state_path}/repo", distro)
      missing = move[:packages] - published
      if !missing.empty?
        abort("ERROR: [#{distro}] packages missing from published archive: #{missing.join(', ')}")
      end
      log_info "[#{distro}] All #{move[:packages].size} packages present in archive"
    end
  end

  def remove_from_live
    @moves.each_pair do |distro, move|
      if move[:whole_distro]
        log_notice "[#{distro}] Dropping distribution from live repository"
        drop_publication(@live_aptly_config_path, distro)
        run_command(
          'aptly', 'repo', 'drop',
          "-config=#{@live_aptly_config_path}",
          distro,
          log_invocation: true,
          check_error: true
        )
      else
        log_notice "[#{distro}] Removing #{move[:packages].size} packages from live repository"
        move[:packages].each_slice(50) do |batch|
          run_command(
            'aptly', 'repo', 'remove',
            "-config=#{@live_aptly_config_path}",
            distro,
            batch.join(' | '),
            log_invocation: false,
            check_error: true
          )
        end
      end
    end
  end

  def publish_all(config_path)
    list_aptly_repos(config_path).each do |distro|
      log_notice "[#{distro}] Publishing #{config_path}"
      publish_aptly_repo(config_path, distro)
    end
  end

  def verify_live
    log_notice 'Verifying live repository'
    remaining_repos = list_aptly_repos(@live_aptly_config_path)
    @moves.each_pair do |distro, move|
      if move[:whole_distro]
        abort("ERROR: [#{distro}] still present in live repository") if remaining_repos.include?(distro)
        if File.exist?("#{@live_state_path}/repo/dists/#{distro}")
          abort("ERROR: [#{distro}] still published in live repository")
        end
      else
        leftover = move[:packages] & list_aptly_packages(@live_aptly_config_path, distro)
        leftover |= move[:packages] & published_packages("#{@live_state_path}/repo", distro)
        if !leftover.empty?
          abort("ERROR: [#{distro}] packages still in live repository: #{leftover.join(', ')}")
        end
      end
    end
  end

  # Package keys (name_version_arch) listed in a published distribution's
  # Packages indexes. This is what APT clients actually see.
  def published_packages(repo_path, distro)
    Dir["#{repo_path}/dists/#{distro}/*/binary-*/Packages"].flat_map do |path|
      File.read(path).split("\n\n").map do |stanza|
        fields = stanza.scan(/^(Package|Version|Architecture): (.+)$/).to_h
        next if fields.empty?
        "#{fields['Package']}_#{fields['Version']}_#{fields['Architecture']}"
      end.compact
    end.uniq
  end

  def list_aptly_repos(config_path)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'repo', 'list',
      "-config=#{config_path}",
      '-raw',
      log_invocation: false,
      check_error: true
    )
    stdout_output.split("\n").map(&:strip).reject(&:empty?)
  end

  def list_aptly_packages(config_path, distro)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'repo', 'show',
      "-config=#{config_path}",
      '-with-packages',
      distro,
      log_invocation: false,
      check_error: true
    )
    stdout_output.sub(/.*^Packages:$/m, '').split("\n").map(&:strip).reject(&:empty?)
  end

  def published?(config_path, distro)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'publish', 'list',
      "-config=#{config_path}",
      '-raw',
      log_invocation: false,
      check_error: true
    )
    stdout_output.split("\n").any? { |line| line.split(' ') == ['filesystem:main:.', distro] }
  end

  def drop_publication(config_path, distro)
    return if !published?(config_path, distro)
    run_command(
      'aptly', 'publish', 'drop',
      "-config=#{config_path}",
      distro, 'filesystem:main:.',
      log_invocation: true,
      check_error: true
    )
  end

  def publish_aptly_repo(config_path, distro)
    # 'aptly publish repo' refuses to overwrite an existing publication,
    # and 'publish update' doesn't add architectures that weren't
    # published before. So we drop and recreate the publication.
    drop_publication(config_path, distro)

    publish_command = [
      'aptly', 'publish', 'repo',
      '-batch', '-force-overwrite',
      "-config=#{config_path}",
      "-gpg-key=#{@gpg_key_id}",
      "-distribution=#{distro}",
      "-origin=#{REPO_ORIGIN}",
      "-label=#{REPO_LABEL}",
    ]
    _, stderr_output, status = run_command_capture_output(
      *publish_command, distro, 'filesystem:main:.',
      log_invocation: true,
      check_error: false
    )
    return if status.success?

    if stderr_output =~ /unable to figure out list of architectures/
      run_command(
        *publish_command, '-architectures=all', distro, 'filesystem:main:.',
        log_invocation: true,
        check_error: true
      )
    else
      abort("ERROR publishing #{distro}: #{stderr_output.chomp}")
    end
  end

  def compact_aptly_db(config_path)
    log_notice "Compacting #{config_path}"
    run_command(
      'aptly', 'db', 'cleanup',
      "-config=#{config_path}",
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def create_state_tarball(state_path, tarball_path)
    log_notice "Creating #{tarball_path}"
    run_bash(
      sprintf("tar -C %s -cf - . | zstd -T0 > %s",
        Shellwords.escape(state_path),
        Shellwords.escape(tarball_path)),
      pipefail: true,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def upload_version(bucket, old_version, state_path, tarball_path)
    new_version = old_version + 1
    version_url = "gs://#{bucket}/versions/#{new_version}"
    log_notice "Uploading #{bucket} version #{new_version}"

    run_command(
      'gsutil', '-h', 'Cache-Control:public',
      'cp', tarball_path, "#{version_url}/state.tar.zst",
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )

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
      "#{state_path}/repo",
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
      log_info "#{distro}: archived #{move[:packages].size} packages#{suffix}"
    end
    log_info "Live repository: version #{@live_version} -> #{@live_version + 1}"
    log_info "Archive repository: version #{@archive_version} -> #{@archive_version + 1}"
    log_info ''
    log_info 'Next steps:'
    log_info '  1. Restart Caddy on the backend server: sudo systemctl restart caddy'
    log_info '     Until then, apt.fullstaqruby.org and apt-archive.fullstaqruby.org serve the old versions.'
    log_info '  2. Verify: curl -fsS https://apt-archive.fullstaqruby.org/dists/<distro>/Release'
  end

  def cleanup
    return if @temp_dir.nil?
    log_info "Cleaning up #{@temp_dir}"
    FileUtils.remove_entry_secure(@temp_dir)
  end
end

ArchiveAptPackages.new.main
