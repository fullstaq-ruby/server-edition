# frozen_string_literal: true

module PublishingSupport
private
  RELOAD_WEB_SERVER_API_URL = 'https://apiserver-f7awo4fcoa-uk.a.run.app/actions/reload_web_server'


  def pull_utility_image_if_not_exists
    # We need the utility image in order to invoke createrepo.
    # We pull it now so that a 'docker run' invocation later doesn't
    # need to pull. This makes the output of the whole script
    # easier to read.
    if !docker_image_exists?(utility_image_name)
      log_notice "Pulling Docker image #{utility_image_name}"
      run_command(
        'docker', 'pull', utility_image_name,
        log_invocation: true,
        check_error: true,
        passthru_output: true
      )
    end
  end

  def docker_image_exists?(image_name)
    _, stderr_output, status = run_command_capture_output(
      'docker', 'inspect', image_name,
      log_invocation: false,
      check_error: false
    )
    if status.success?
      true
    elsif stderr_output =~ /No such object/
      false
    else
      abort("Command failed: docker inspect #{image_name}: #{stderr_output.chomp}")
    end
  end


  def fetch_signing_key
    key, _, _ = run_command_capture_output(
      'gcloud', 'secrets', 'versions', 'access', 'latest',
      '--secret', 'gpg-private-key',
      log_invocation: true,
      check_error: true
    )
    key
  end

  def infer_gpg_key_id(gpg_home, key_path)
    stdout_output, _, _ = run_command_capture_output(
      'gpg', '--homedir', gpg_home, '--show-keys', key_path,
      log_invocation: true,
      check_error: true
    )
    stdout_output.split("\n")[1].strip
  end

  def import_gpg_key(gpg_home, key_path)
    run_command(
      'gpg', '--homedir', gpg_home, '--import', key_path,
      log_invocation: true,
      check_error: true
    )
  end


  def utility_image_name
    "ghcr.io/fullstaq-ruby/server-edition-ci-images:utility-v#{utility_image_version}"
  end

  def utility_image_version
    read_single_value_file("#{GeneralSupport::ROOT}/environments/utility/image_tag")
  end


  def get_latest_production_repo_version
    if (version = getenv_integer('LATEST_PRODUCTION_REPO_VERSION')).nil?
      stdout_output, stderr_output, status = run_command_capture_output(
        'gsutil', 'cp', latest_production_version_note_url, '-',
        log_invocation: false,
        check_error: false
      )
      if status.success?
        version = stdout_output.strip
        if version =~ /\A[0-9]+\Z/
          version = version.to_i
        else
          abort("ERROR: invalid version number stored in #{latest_production_version_note_url}")
        end
      elsif stderr_output =~ /No URLs matched/
        version = 0
      else
        abort("ERROR: error fetching #{latest_production_version_note_url}: #{stderr_output.chomp}")
      end
    end

    log_notice "Latest state/repository version is: #{version}"
    version
  end


  def cache_control_policy
    if testing?
      'no-store'
    else
      'public'
    end
  end


  def gcloud_identity_token
    stdout_output, _, _ = run_command_capture_output(
      'gcloud', 'auth', 'print-identity-token',
      log_invocation: false,
      check_error: true
    )
    stdout_output.strip
  end

  def restart_web_servers
    log_notice 'Restarting web servers'

    success = false

    log_info "POSTing to #{RELOAD_WEB_SERVER_API_URL}"
    run_command_stream_output(
      'curl', '-fsSLN',
      '-D', '-',
      '-X', 'POST',
      '-H', "Authorization: Bearer #{gcloud_identity_token}",
      RELOAD_WEB_SERVER_API_URL,
      log_invocation: false,
      check_error: true
    ) do |output|
      while !output.eof?
        line = output.readline.chomp
        log_info(line)
        success = true if line == "event: success"
      end
    end

    if !success
      abort('ERROR: failed to restart web server')
    end
  end
end
