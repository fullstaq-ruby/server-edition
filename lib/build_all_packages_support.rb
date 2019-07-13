require 'yaml'
require 'shellwords'
require 'fileutils'
require 'stringio'
require 'rbconfig'
require 'paint'
require 'paint/rgb_colors'
require_relative 'progress_tracker'

module Support
  ROOT = File.absolute_path(File.dirname(__FILE__) + '/..')
  OUTPUT_MUTEX = Mutex.new

  class << self
    attr_reader :config

    def load_config
      @config = YAML.safe_load(File.read(config_file_path, encoding: 'utf-8'))
      @config = recursively_symbolize_keys(@config)
      FileUtils.mkdir_p(cache_dir)
      FileUtils.mkdir_p(output_dir)
      FileUtils.mkdir_p(logs_dir)
    end


    def cache_dir
      @config[:cache_dir]
    end

    def output_dir
      @config[:output_dir]
    end

    def logs_dir
      @config[:logs_dir]
    end


    def distributions
      @distributions ||= begin
        if @config[:distributions] == 'all'
          envs = Dir["#{ROOT}/environments/*"].map do |path|
            File.basename(path)
          end
          envs.delete('utility')
          names = envs
        elsif @config[:distributions].is_a?(Array)
          names = @config[:distributions]
        else
          abort "Config error: 'distributions' must be set to 'all' or to a list"
        end

        names.map do |name|
          {
            name: name,
            package_format: autodetect_package_format(name)
          }
        end
      end
    end

    def variants
      @variants ||= begin
        result = []
        if @config[:variants][:normal]
          result << {
            name: 'normal',
            package_suffix: ''
          }
        end
        if @config[:variants][:jemalloc]
          result << {
            name: 'jemalloc',
            package_suffix: '-jemalloc'
          }
        end
        if @config[:variants][:malloctrim]
          result << {
            name: 'malloctrim',
            package_suffix: '-malloctrim'
          }
        end
        result
      end
    end

    def determine_test_image_for(distro)
      dockerfile = File.read("#{ROOT}/environments/#{distro[:name]}/Dockerfile",
        encoding: 'utf-8')
      dockerfile =~ /FROM (.+)/
      $1
    end


    def rbenv_version
      @rbenv_version ||= begin
        output = capture_output("#{rbenv_source_path}/bin/rbenv", "--version").strip
        output.split(' ')[1].sub(/(.+)-.*/, '\1')
      end
    end

    def rbenv_package_revision
      @config[:rbenv][:package_revision]
    end

    def rbenv_source_path
      @rbenv_source_path ||= begin
        if @config[:rbenv][:repo]
          checkout_rbenv_from_git(@config[:rbenv][:repo], @config[:rbenv][:ref])
        else
          @config[:rbenv][:path] ||
            abort("Config error: either 'rbenv.repo' + 'rbenv.ref' must be specified, or 'rbenv.path' must be specified")
        end
      end
    end

    def rbenv_deb_path
      rbenv_package_path(:DEB)
    end

    def rbenv_rpm_path
      rbenv_package_path(:RPM)
    end

    def rbenv_package_path(package_format)
      case package_format
      when :DEB
        "#{output_dir}/fullstaq-rbenv_#{rbenv_version}_#{rbenv_package_revision}_all.deb"
      when :RPM
        "#{output_dir}/fullstaq-rbenv-#{rbenv_version}-#{rbenv_package_revision}.noarch.rpm"
      else
        raise "Unsupported package format: #{package_format.inspect}"
      end
    end


    def jemalloc_source_basename
      "jemalloc-#{@config[:jemalloc_version]}.tar.bz2"
    end

    def jemalloc_source_url
      "https://github.com/jemalloc/jemalloc/releases/download/#{@config[:jemalloc_version]}/#{jemalloc_source_basename}"
    end

    def jemalloc_source_path
      "#{cache_dir}/#{jemalloc_source_basename}"
    end

    def jemalloc_bin_path(distro)
      "#{output_dir}/jemalloc-bin-#{@config[:jemalloc_version]}-#{distro[:name]}.tar.gz"
    end


    def ruby_source_versions
      @ruby_source_versions ||= begin
        result = []
        result << (@config[:ruby][:minor_version_packages] || []).map do |entry|
          entry[:full_version]
        end
        result << (@config[:ruby][:tiny_version_packages] || []).map do |entry|
          entry[:full_version]
        end
        result.flatten!
        result.uniq!
        result
      end
    end

    def ruby_package_versions
      @ruby_package_versions ||= begin
        all = (@config[:ruby][:minor_version_packages] || []) +
          (@config[:ruby][:tiny_version_packages] || [])
        all.map do |entry|
          entry = entry.dup
          entry[:id] = entry[:minor_version] || entry[:full_version]
          entry
        end
      end
    end

    def ruby_source_basename(source_version)
      "ruby-#{source_version}.tar.gz"
    end

    def ruby_source_url(source_version)
      minor_version = source_version.sub(/(.+)\..*/, '\1')
      "https://cache.ruby-lang.org/pub/ruby/#{minor_version}/#{ruby_source_basename(source_version)}"
    end

    def ruby_source_path(source_version)
      "#{cache_dir}/#{ruby_source_basename(source_version)}"
    end

    def ruby_source_path_for_package_version(package_version)
      "#{cache_dir}/ruby-#{package_version[:full_version]}.tar.gz"
    end

    def ruby_bin_path(package_version, distro, variant)
      "#{output_dir}/ruby-bin-#{package_version[:id]}-#{distro[:name]}-#{variant[:name]}.tar.gz"
    end

    def ruby_package_path(package_version, distro, variant)
      case distro[:package_format]
      when :DEB
        "#{output_dir}/fullstaq-ruby_#{package_version[:id]}#{variant[:package_suffix]}_#{package_version[:package_revision]}-#{distro[:name]}_#{deb_arch}.deb"
      when :RPM
        "#{output_dir}/fullstaq-ruby-#{package_version[:id]}#{variant[:package_suffix]}-rev#{package_version[:package_revision]}-#{sanitize_distro_name_for_rpm(distro[:name])}.#{rpm_arch}.rpm"
      else
        raise "Unsupported package format: #{package_format.inspect}"
      end
    end


    def initialize_progress_tracking
      @progress_tracker = ProgressTracker.new
      @progress_tracker_pipe = IO.pipe
      @exiting = false
    end

    def start_progress_tracking
      @progress_tracker_bg_thread = Thread.new do
        while ! @progress_tracker.mutex.synchronize { @exiting }
          write_progress_summary_logs
          IO.select([@progress_tracker_pipe[0]], nil, nil, 5)
        end

        @progress_tracker_pipe[0].close
        write_progress_summary_logs
      end
    end

    def stop_progress_tracking
      @progress_tracker.mutex.synchronize do
        @exiting = true
      end
      @progress_tracker_pipe[1].write('x')
      @progress_tracker_pipe[1].flush
      @progress_tracker_pipe[1].close
      @progress_tracker_bg_thread.join
    end

    def define_progress_category(name, &block)
      @progress_tracker.define_category(name, &block)
    end


    def sh(*command)
      if stage = Thread.current[:progress_tracking_stage]
        log "--> Running: #{Shellwords.shelljoin(command)}"
        spawn_opts = {
          in: '/dev/null',
          err: [:child, :out],
          close_others: true
        }
        IO.popen(command + [spawn_opts], 'rb') do |io|
          io.each_line do |line|
            line.chomp!
            if line =~ /^\e\[44m\e\[33m\e\[1m/
              # Looks like a header. Replace color codes with an ASCII
              # indicator.
              line.sub!(/^\e\[44m\e\[33m\e\[1m/, '--> ')
              line.sub!("\e[0m", '')
            end
            log("    #{line}".encode(invalid: :replace))
          end
        end
        if $?.exitstatus != 0
          log "*** ERROR: command failed: #{Shellwords.shelljoin(command)}"
          abort
        end
      else
        STDERR.puts "--> Running: #{Shellwords.shelljoin(command)}"
        if !system(*command)
          abort "--> *** ERROR: command failed!"
        end
      end
    end

    def has_wget?
      return @has_wget if defined?(@has_wget)
      @has_wget = !!find_command('wget')
    end

    def has_curl?
      return @has_curl if defined?(@has_curl)
      @has_curl = !!find_command('curl')
    end

    def download(url, output)
      if has_curl?
        sh 'curl', '-fSLo', output, url
      elsif has_wget?
        sh 'wget', '-O', output, url
      else
        log "*** ERROR: Cannot download #{url}: no curl or wget installed"
        abort
      end
    end

    # Various scripts leave behind an empty output file on error.
    # To make sure the next build-everything invocation doesn't skip
    # generating those files, we delete such empty files.
    def delete_empty_file(path)
      if File.stat(path).size == 0
        File.unlink(path)
      end
    rescue Errno::ENOENT
    end

    def log(message)
      stage = Thread.current[:progress_tracking_stage] ||
        raise("BUG: ProgressTracker must be tracking")

      prefix = Paint[stage.id.ljust(40) + " | ", stage.color]
      prefixed_message = "#{prefix}#{message}\n"
      timestamp = format_time(Time.now)
      timestamped_message = "#{timestamp} | #{message}\n"

      OUTPUT_MUTEX.synchronize do
        STDERR.write(prefixed_message)
        STDERR.flush
        stage.log_file.write(timestamped_message)
        stage.log_file.flush
      end
    end

    def print_line
      STDERR.puts '---------------------------------------------------'
    end

    def format_time(time)
      time.strftime("%Y-%m-%d %H:%M:%S")
    end

    def distance_of_time_in_hours_and_minutes(from_time, to_time)
      from_time = from_time.to_time if from_time.respond_to?(:to_time)
      to_time = to_time.to_time if to_time.respond_to?(:to_time)
      dist = (to_time - from_time).to_i
      minutes = (dist.abs / 60).round
      hours = minutes / 60
      minutes = minutes - (hours * 60)
      seconds = dist - (hours * 3600) - (minutes * 60)

      words = ''
      words << "#{hours} #{hours > 1 ? 'hours' : 'hour' } " if hours > 0
      words << "#{minutes} min " if minutes > 0
      words << "#{seconds} sec"
      words
    end

  private
    def config_file_path
      @config_file_path ||= ENV.fetch('CONFIG', "#{ROOT}/config.yml")
    end

    def capture_output(*command)
      data = IO.popen(command + [in: :in], encoding: 'utf-8') do |io|
        io.read
      end
      if $?.exitstatus != 0
        abort "Command failed: #{Shellwords.shelljoin(command)}"
      end
      data
    end

    def checkout_rbenv_from_git(repo, ref)
      path = "#{cache_dir}/rbenv"
      STDERR.puts "--> Checking out Rbenv from #{repo} ref #{ref}, to #{path}..."
      if File.exist?(path)
        Dir.chdir(path) do
          sh('git', 'remote', 'set-url', 'origin', repo)
          sh('git', 'fetch', 'origin')
        end
      else
        sh('git', 'clone', repo, path)
      end
      Dir.chdir(path) do
        sh('git', 'reset', '--hard', ref)
      end
      path
    end

    def autodetect_package_format(environment)
      dockerfile = File.read("#{ROOT}/environments/#{environment}/Dockerfile",
        encoding: 'utf-8')
      if dockerfile =~ /yum install/
        :RPM
      else
        :DEB
      end
    end

    def sanitize_distro_name_for_rpm(distro_name)
      distro_name.gsub('-', '')
    end

    def recursively_symbolize_keys(thing)
      case thing
      when Array
        thing.map do |entry|
          recursively_symbolize_keys(entry)
        end
      when Hash
        result = {}
        thing.each_pair do |k, v|
          result[k.to_sym] = recursively_symbolize_keys(v)
        end
        result
      else
        thing
      end
    end

    def deb_arch
      @deb_arch ||= begin
        if on_macos?
          # Assuming macOS with Docker for Mac
          return 'amd64'
        end

        arch = cpu_architecture
        case arch
        when 'x86'
          'i386'
        when 'x86_64'
          'amd64'
        else
          arch
        end
      end
    end

    def rpm_arch
      @rpm_arch ||= begin
        if on_macos?
          # Assuming macOS with Docker for Mac
          return 'x86_64'
        end

        arch = cpu_architecture
        case arch
        when 'x86'
          'i686'
        else
          arch
        end
      end
    end

    def on_macos?
      RbConfig::CONFIG['target_os'] =~ /darwin/ && File.exist?('/usr/bin/sw_vers')
    end

    def cpu_architecture
      @cpu_architecture ||= begin
        arch = `uname -p`.strip
        # On some systems 'uname -p' returns something like
        # 'Intel(R) Pentium(R) M processor 1400MHz' or
        # 'Intel(R)_Xeon(R)_CPU___________X7460__@_2.66GHz'.
        if arch == "unknown" || arch =~ / / || arch =~ /Hz$/
          arch = `uname -m`.strip
        end
        if arch =~ /^i.86$/
          'x86'
        elsif arch == 'amd64'
          'x86_64'
        else
          arch
        end
      end
    end

    def find_command(name)
      ENV['PATH'].split(':').each do |dir|
        if File.executable?("#{dir}/#{name}")
          return "#{dir}/#{name}"
        end
      end
      nil
    end

    def write_progress_summary_logs
      buf_colorized = StringIO.new
      buf_nocolor = StringIO.new
      @progress_tracker.write(buf_colorized, true)
      @progress_tracker.write(buf_nocolor, false)

      File.open("#{logs_dir}/summary.log", 'w:utf-8') do |f|
        f.write(buf_nocolor.string)
      end
      File.open("#{logs_dir}/summary-color.log", 'w:utf-8') do |f|
        f.write(buf_colorized.string)
      end

      OUTPUT_MUTEX.synchronize do
        print_line
        STDERR.write(buf_colorized.string)
        print_line
      end
    end
  end
end
