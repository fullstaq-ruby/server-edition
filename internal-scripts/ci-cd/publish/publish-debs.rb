#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../../lib/gcloud_storage_lock'
require_relative '../../../lib/build_all_packages_support'
require_relative '../../../lib/shell_scripting_support'
require_relative '../../../lib/publishing_support'
require 'json'
require 'shellwords'
require 'tmpdir'
require 'set'

class PublishDebs
  include ShellScriptingSupport
  include PublishingSupport

  def main
    require_envvar 'PRODUCTION_REPO_BUCKET_NAME'
    require_envvar 'TESTING'
    require_envvar 'OVERWRITE_EXISTING'
    if testing?
      require_envvar 'CI_ARTIFACTS_BUCKET_NAME'
      require_envvar 'CI_ARTIFACTS_RUN_NUMBER'
    end
    optional_envvar 'DRY_RUN'
    optional_envvar 'REMOTE_STATE_URL'
    optional_envvar 'LATEST_PRODUCTION_REPO_VERSION'
    @package_paths = ARGV

    print_header 'Initializing'
    Support.load_config
    group_packages_by_distro_and_canonicalize_names
    create_temp_dirs
    ensure_gpg_state_isolated
    activate_wrappers_bin_dir
    initialize_locking
    initialize_aptly
    fetch_and_import_signing_key

    version = nil
    imported = nil
    skipped = nil

    synchronize do
      version = @orig_version = get_latest_production_repo_version
      fetch_state(version) if version != 0

      print_header 'Modifying repository state'
      imported, skipped = import_packages_into_state
      if imported == 0
        log_notice 'No packages imported'
        exit
      end
      compact_state
      archive_state
      check_lock_health

      print_header 'Creating repository'
      create_repo
      check_lock_health

      if !dry_run?
        print_header 'Uploading changes'
        save_state(version + 1)
        save_repo(version + 1)
        create_version_note(version + 1)
        check_lock_health

        print_header 'Activating changes'
        declare_latest_version(version + 1)
        restart_web_servers if !testing?
      end
    end

    print_header 'Success!'
    print_stats(imported, skipped)
    if dry_run?
      log_notice 'Dry running, so not uploading changes'
    else
      print_conclusion(version + 1)
    end
  end

private
  def testing?
    getenv_boolean('TESTING')
  end

  def dry_run?
    getenv_boolean('DRY_RUN')
  end

  def group_packages_by_distro_and_canonicalize_names
    @packages_by_distro = {}
    @package_paths.each do |path|
      distro, canonical_name = infer_package_distro_and_canonical_name(path)
      if distro
        distros = [distro]
      else
        distros = all_supported_distros
      end

      distros.each do |distro|
        packages = (@packages_by_distro[distro] ||= [])
        packages << {
          path: path,
          canonical_name: canonical_name
        }
      end
    end

    log_notice "Grouped #{@package_paths.size} packages into #{@packages_by_distro.size} distributions"
    @packages_by_distro.each_pair do |distro, packages|
      log_info "#{distro}:"
      packages.map{ |p| p[:path] }.sort.each do |path|
        log_info " - #{path}"
      end
    end
  end

  def infer_package_distro_and_canonical_name(path)
    stdout_output, stderr_output, status = run_command_capture_output(
      'dpkg', '-I', path,
      log_invocation: false,
      check_error: false
    )

    if !status.success?
      abort "Error inspecting #{path}: #{stderr_output.chomp}"
    end

    if stdout_output =~ /^  Distribution: (.+)/
      distro = $1
    else
      distro = nil
    end

    if stdout_output !~ /^ Package: (.+)/
      abort "Error inspecting #{path}: could not infer package name"
    end
    package_name = $1

    if stdout_output !~ /^ Version: (.+)/
      abort "Error inspecting #{path}: could not infer package version"
    end
    version = $1

    if stdout_output !~ /^ Architecture: (.+)/
      abort "Error inspecting #{path}: could not infer package architecture"
    end
    arch = $1

    [distro, "#{package_name}_#{version}_#{arch}"]
  end

  def all_supported_distros
    Support.distributions.find_all{ |d| d[:package_format] == :DEB }.map{ |d| d[:name] }
  end

  def create_temp_dirs
    log_notice 'Creating temporary directories'
    @temp_dir = Dir.mktmpdir
    @wrappers_bin_dir = "#{@temp_dir}/wrappers"
    @aptly_config_path = "#{@temp_dir}/aptly.conf"
    @signing_key_path = "#{@temp_dir}/key.gpg"
    @local_state_path = "#{@temp_dir}/state"
    @local_state_db_path = "#{@local_state_path}/db"
    @local_state_repo_path = "#{@local_state_path}/repo"
    @local_state_archive_path = "#{@temp_dir}/state.tar.zst"

    Dir.mkdir(@wrappers_bin_dir)
    Dir.mkdir(@local_state_path)
    Dir.mkdir(@local_state_db_path)
    Dir.mkdir(@local_state_repo_path)
  end

  def ensure_gpg_state_isolated
    # We ensure that GPG invocations use an isolated state
    # by creating a wrapper script that calls 'gpg --homedir'
    # with a temporary directory.

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
      if File.exist?(candidate)
        return candidate
      end
    end
    abort('GPG not found')
  end

  def activate_wrappers_bin_dir
    ENV['PATH'] = "#{@wrappers_bin_dir}:#{ENV['PATH']}"
  end

  def initialize_locking
    if !testing?
      @lock = GCloudStorageLock.new(url: lock_url)
    end
  end

  def initialize_aptly
    log_notice 'Creating Aptly config file'
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

  def lock_url
    "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/locks/apt"
  end

  def synchronize
    if testing?
      yield
    else
      @lock.synchronize do
        yield
      end
    end
  end

  def check_lock_health
    return if testing?
    abort 'ERROR: lock is unhealthy. Aborting operation' if !@lock.healthy?
  end

  def latest_version_note_url
    if testing?
      latest_testing_version_note_url
    else
      latest_production_version_note_url
    end
  end

  def latest_production_version_note_url
    "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/latest_version.txt"
  end

  def latest_testing_version_note_url
    "gs://#{ENV['CI_ARTIFACTS_BUCKET_NAME']}/#{ENV['CI_ARTIFACTS_RUN_NUMBER']}/apt-repo/versions/latest_version.txt"
  end

  def version_note_url(version)
    if testing? && version != @orig_version
      "gs://#{ENV['CI_ARTIFACTS_BUCKET_NAME']}/#{ENV['CI_ARTIFACTS_RUN_NUMBER']}/apt-repo/versions/singleton/version.txt"
    else
      "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/#{version}/version.txt"
    end
  end

  def remote_state_url(version)
    value = ENV['REMOTE_STATE_URL']
    return value if value

    if testing? && version != @orig_version
      "gs://#{ENV['CI_ARTIFACTS_BUCKET_NAME']}/#{ENV['CI_ARTIFACTS_RUN_NUMBER']}/apt-repo/versions/singleton/state.tar.zst"
    else
      "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/#{version}/state.tar.zst"
    end
  end

  def remote_repo_url(version)
    if testing? && version != @orig_version
      "gs://#{ENV['CI_ARTIFACTS_BUCKET_NAME']}/#{ENV['CI_ARTIFACTS_RUN_NUMBER']}/apt-repo/versions/singleton/public"
    else
      "gs://#{ENV['PRODUCTION_REPO_BUCKET_NAME']}/versions/#{version}/public"
    end
  end

  def remote_repo_public_url(version)
    remote_repo_url(version).sub(%r(^gs://), 'https://storage.googleapis.com/')
  end

  def fetch_state(version)
    log_notice 'Fetching state'

    run_bash(
      sprintf('gsutil -m cp %s - | zstd -dc | tar -xC %s',
        Shellwords.escape(remote_state_url(version)),
        Shellwords.escape(@local_state_path)),
      pipefail: true,
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def import_packages_into_state
    imported = 0
    skipped = 0
    @packages_by_distro.each_pair do |distro, packages|
      imported2, skipped2 = import_packages_into_state_for_distro(distro, packages)
      imported += imported2
      skipped += skipped2
    end
    [imported, skipped]
  end

  def import_packages_into_state_for_distro(distro, packages)
    log_notice "[#{distro}] Importing #{packages.size} packages"

    if !aptly_repo_exists?(distro)
      create_aptly_repo(distro)
    end

    if getenv_boolean('OVERWRITE_EXISTING')
      args = ['-force-replace']
      package_paths = packages.map { |p| p[:path] }
      imported = package_paths.size
      skipped = 0
    else
      args = []
      package_paths = filter_existing_packages(distro, packages)
      imported = package_paths.size
      skipped = packages.size - package_paths.size
    end

    if package_paths.any?
      run_command(
        'aptly', 'repo', 'add', *args,
        "-config=#{@aptly_config_path}",
        aptly_repo_name(distro),
        *package_paths,
        log_invocation: true,
        check_error: true,
      )
    end

    [imported, skipped]
  end

  def filter_existing_packages(distro, packages)
    existing_packages = Set.new(list_aptly_packages(distro))
    result = []

    packages.each do |package|
      if existing_packages.include?(package[:canonical_name])
        log_info "     #{YELLOW}SKIP#{RESET} #{package[:path]}: package already in repository"
      else
        log_info "  #{GREEN}INCLUDE#{RESET} #{package[:path]}"
        result << package[:path]
      end
    end

    result
  end

  def list_aptly_packages(distro)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'repo', 'show',
      "-config=#{@aptly_config_path}",
      '-with-packages',
      distro,
      log_invocation: false,
      check_error: true
    )

    stdout_output.sub!(/.*^Packages:$/m, '')
    stdout_output.split("\n").map { |l| l.strip }
  end

  def compact_state
    log_notice 'Compacting state'

    run_command(
      'aptly', 'db', 'cleanup',
      "-config=#{@aptly_config_path}",
      '-verbose',
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def archive_state
    log_notice 'Creating state archive'

    run_bash(
      sprintf(
        "tar -C %s -cf - . | zstd -T0 > %s",
        Shellwords.escape(@local_state_path),
        Shellwords.escape(@local_state_archive_path)
      ),
      pipefail: true,
      log_invocation: true,
      check_error: true,
      passthru_output: true,
    )
  end

  def aptly_repo_exists?(distro)
    stdout_output, _, _ = run_command_capture_output(
      'aptly', 'repo', 'list', '-raw',
      "-config=#{@aptly_config_path}",
      log_invocation: false,
      check_error: true
    )
    stdout_output.split("\n").include?(distro)
  end

  def create_aptly_repo(distro)
    run_command(
      'aptly', 'repo', 'create',
      "-config=#{@aptly_config_path}",
      distro,
      log_invocation: true,
      check_error: true
    )
  end

  def aptly_repo_name(distro)
    distro
  end

  def create_repo
    @packages_by_distro.each_key do |distro|
      create_repo_for_distro(distro)
    end
  end

  def create_repo_for_distro(distro)
    log_notice "[#{distro}] Creating repository"

    # The strategy is to create brand-new publications every time
    # instead of using 'aptly publish update'. Recreating
    # publications every time is slower than using 'update', but
    # we avoid an important caveat:
    # 'update' doesn't add packages for architectures that weren't
    # already in the publication.

    _, stderr_output, status = run_command_capture_output(
      'aptly', 'publish', 'repo',
      '-batch', '-force-overwrite',
      "-config=#{@aptly_config_path}",
      "-gpg-key=#{@gpg_key_id}",
      "-distribution=#{distro}",
      aptly_repo_name(distro), 'filesystem:main:.',
      log_invocation: true,
      check_error: false
    )
    if !status.success?
      if stderr_output =~ /unable to figure out list of architectures/
        run_command_capture_output(
          'aptly', 'publish', 'repo',
          '-batch', '-force-overwrite', '-architectures=all',
          "-config=#{@aptly_config_path}",
          "-gpg-key=#{@gpg_key_id}",
          "-distribution=#{distro}",
          aptly_repo_name(distro), 'filesystem:main:.',
          log_invocation: true,
          check_error: true
        )
      else
        abort("ERROR: #{stderr_output.chomp}")
      end
    end
  end

  def save_state(version)
    log_notice "Saving state (as version #{version})"

    run_command(
      'gsutil',
      '-h', "Cache-Control:#{cache_control_policy}",
      'cp',
      @local_state_archive_path,
      remote_state_url(version),
      log_invocation: true,
      check_error: true,
      passthru_output: true,
    )
  end

  def save_repo(version)
    log_notice "Saving repository (as version #{version})"

    if !testing? && version != 0
      log_info "Copying over version #{version - 1}"
      run_command(
        'gsutil', '-m',
        '-h', "Cache-Control:#{cache_control_policy}",
        'rsync', '-r', '-d',
        remote_repo_url(version - 1),
        remote_repo_url(version),
        log_invocation: true,
        check_error: true,
        passthru_output: true
      )

      log_info "Uploading version #{version}"
    end

    run_command(
      'gsutil', '-m',
      '-h', "Cache-Control:#{cache_control_policy}",
      'rsync', '-r', '-d',
      @local_state_repo_path,
      remote_repo_url(version),
      log_invocation: true,
      check_error: true,
      passthru_output: true
    )
  end

  def create_version_note(version)
    log_notice 'Creating version note'

    run_bash(
      sprintf(
        'gsutil -q ' \
        '-h Content-Type:text/plain ' \
        "-h Cache-Control:#{cache_control_policy} " \
        'cp - %s <<<%s',
        Shellwords.escape(version_note_url(version)),
        Shellwords.escape(version.to_s)
      ),
      log_invocation: true,
      check_error: true,
      pipefail: false
    )
  end

  def declare_latest_version(version)
    log_notice "Declaring that latest state/repository version is #{version}"

    run_bash(
      sprintf(
        'gsutil -q ' \
        '-h Content-Type:text/plain ' \
        '-h Cache-Control:no-store ' \
        'cp - %s <<<%s',
        Shellwords.escape(latest_version_note_url),
        Shellwords.escape(version.to_s)
      ),
      log_invocation: true,
      check_error: true,
      pipefail: false
    )
  end

  def print_stats(imported, skipped)
    log_notice "Statistics"
    log_info "Packages imported: #{imported}"
    log_info "Packages skipped : #{skipped}"
  end

  def print_conclusion(version)
    log_notice "The APT repository is now live at: #{remote_repo_public_url(version)}"
  end
end

PublishDebs.new.main
