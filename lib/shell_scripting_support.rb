# frozen_string_literal: true

require 'open3'
require 'shellwords'

module ShellScriptingSupport
private
  RESET = "\033[0m"
  BOLD = "\033[1m"
  BLUE_BG = "\033[44m"
  GREEN = "\033[32m"
  YELLOW = "\033[33m"


  def require_envvar(name)
    if ENV[name].to_s.empty?
      abort "ERROR: please pass the '#{name}' environment variable to this script."
    end
  end

  def optional_envvar(name)
    # Does nothing. Only exists to signal intent.
  end

  def getenv_boolean(name)
    value = ENV[name].to_s.downcase
    ['true', 't', 'yes', 'y', '1', 'on'].include?(value)
  end

  def getenv_integer(name, default = nil)
    value = ENV[name].to_s
    if value =~ /\A[0-9]+\Z/
      value.to_i
    else
      default
    end
  end


  def print_header(title)
    puts
    puts "#{BLUE_BG}#{YELLOW}#{BOLD}#{title}#{RESET}"
    puts '------------------------------------------'
  end

  def log_notice(message)
    puts " --> #{message}"
  end

  def log_info(message)
    puts "     #{message}"
  end

  def abort(message)
    puts "     #{message}"
    exit 1
  end


  def run_command(*command, log_invocation:, check_error:, passthru_output: false)
    log_info "Running: #{Shellwords.shelljoin(command)}" if log_invocation
    if passthru_output
      # Force system() to run without shell
      success = system([command[0], command[0]], *command[1..-1])
      abort('ERROR: command failed') if check_error && !success
    else
      output, status = Open3.capture2e(*command)
      abort("ERROR: #{output.chomp}") if check_error && !status.success?
    end
  end

  def run_bash(script, *args, log_invocation:, check_error:, pipefail:, passthru_output: false)
    log_info "Running: #{script}" if log_invocation
    script = "set -o pipefail && #{script}" if pipefail
    if passthru_output
      success = system('bash', '-ec', script, 'bash', *args)
      abort('ERROR: command failed') if check_error && !success
    else
      output, status = Open3.capture2e('bash', '-ec', script, 'bash', *args)
      abort("ERROR: #{output.chomp}") if check_error && !status.success?
    end
  end

  def run_command_capture_output(*command, log_invocation:, check_error:)
    log_info "Running: #{Shellwords.shelljoin(command)}" if log_invocation
    stdout_output, stderr_output, status = Open3.capture3(*command)
    abort("ERROR: #{stderr_output.chomp}") if check_error && !status.success?
    [stdout_output, stderr_output, status]
  end

  def run_command_stream_output(*command, log_invocation:, check_error:)
    log_info "Running: #{Shellwords.shelljoin(command)}" if log_invocation
    Open3.popen2e(*command) do |stdin, output, wait_thr|
      stdin.close
      yield output
      status = wait_thr.value
      abort('ERROR: command failed') if check_error && !status.success?
      status
    end
  end


  class HardLinkError < StandardError
    attr_reader :source_path, :target_path, :cause

    def initialize(message, source_path, target_path, cause)
      super(message)
      @source_path = source_path
      @target_path = target_path
      @cause = cause
    end
  end

  # @return [Boolean]
  # @raise [HardLinkError, SystemCallError]
  def create_hardlink(source_path, target_path)
    File.unlink(target_path) if File.exist?(target_path)
    begin
      File.link(source_path, target_path)
      true
    rescue Errno::EXDEV, Errno::EPERM
      # These errors potentially indicate that hard linking is not supported.
      false
    rescue SystemCallError => e
      raise HardLinkError.new(
        "Error hard linking #{source_path} into #{target_path}: #{e}",
        source_path,
        target_path,
        e
      )
    end
  end

  # @raise [HardLinkError, SystemCallError]
  def hardlink_or_copy_file(source_path, target_path)
    if !create_hardlink(source_path, target_path)
      FileUtils.cp(source_path, target_path, preserve: true)
    end
  end

  # @raise [HardLinkError, SystemCallError]
  def hardlink_or_copy_files(paths, target_dir)
    paths.each do |source_path|
      target_path = "#{target_dir}/#{File.basename(source_path)}"
      hardlink_or_copy_file(source_path, target_path)
    end
  end

  def delete_files(glob:)
    Dir[glob].each do |path|
      File.unlink(path)
    end
  end
end
