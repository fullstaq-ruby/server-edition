require 'yaml'
require 'shellwords'
require 'fileutils'
require 'stringio'
require 'rbconfig'

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
          envs.sort!
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

    def distributions_with_test_image_info
      distributions.map do |distro|
        distro.merge(
          test_image: determine_test_image_for(distro)
        )
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


    def apt_repo_base_url
      ENV['APT_REPO_BASE_URL'] || 'https://apt.fullstaqruby.org'
    end

    def yum_repo_base_url
      ENV['YUM_REPO_BASE_URL'] || 'https://yum.fullstaqruby.org'
    end


    def checkout_rbenv_if_necessary
      if @config[:rbenv][:repo]
        checkout_rbenv_from_git(@config[:rbenv][:repo], @config[:rbenv][:ref])
      end
    end

    def verify_rbenv_version_in_config
      if rbenv_version_according_to_source != rbenv_version
        abort("Config error: 'rbenv.version' is set to #{rbenv_version.inspect}," \
            " but it should be #{rbenv_version_according_to_source.inspect}")
      end
    end

    def rbenv_version_according_to_source
      @rbenv_version_according_to_source ||= begin
        output = capture_output("#{rbenv_source_path}/bin/rbenv", "--version").strip
        output.split(' ')[1].sub(/(.+)-.*/, '\1')
      end
    end

    def rbenv_version
      @config[:rbenv][:version]
    end

    def rbenv_package_revision
      @config[:rbenv][:package_revision]
    end

    def rbenv_source_path
      @rbenv_source_path ||= begin
        if @config[:rbenv][:repo]
          "#{cache_dir}/rbenv"
        else
          @config[:rbenv][:path] ||
            abort("Config error: either 'rbenv.repo' + 'rbenv.ref' must be specified, or 'rbenv.path' must be specified")
        end
      end
    end

    def rbenv_deb_basename
      rbenv_package_basename(:DEB)
    end

    def rbenv_deb_path
      rbenv_package_path(:DEB)
    end

    def rbenv_deb_possible_repo_urls
      distributions.find_all do |distro|
        distro[:package_format] == :DEB
      end.map do |distro|
        rbenv_package_repo_url(distro)
      end.uniq
    end

    def rbenv_rpm_basename
      rbenv_package_basename(:RPM)
    end

    def rbenv_rpm_path
      rbenv_package_path(:RPM)
    end

    def rbenv_rpm_possible_repo_urls
      distributions.find_all do |distro|
        distro[:package_format] == :RPM
      end.map do |distro|
        rbenv_package_repo_url(distro)
      end.uniq
    end

    def rbenv_package_basename(package_format)
      case package_format
      when :DEB
        "fullstaq-rbenv_#{rbenv_version}-#{rbenv_package_revision}_all.deb"
      when :RPM
        "fullstaq-rbenv-#{rbenv_version}-#{rbenv_package_revision}.noarch.rpm"
      else
        raise "Unsupported package format: #{package_format.inspect}"
      end
    end

    def rbenv_package_path(package_format)
      "#{output_dir}/#{rbenv_package_basename(package_format)}"
    end

    def rbenv_package_repo_url(distro)
      basename = rbenv_package_basename(distro[:package_format])
      case distro[:package_format]
      when :DEB
        "#{apt_repo_base_url}/#{basename}"
      when :RPM
        "#{yum_repo_base_url}/#{distro[:name]}/#{rpm_arch}/#{basename}"
      else
        raise "Unsupported package format: #{distro[:package_format].inspect}"
      end
    end


    def common_deb_version
      @config[:common][:deb][:version]
    end

    def common_deb_package_revision
      @config[:common][:deb][:package_revision]
    end

    def common_deb_basename
      common_package_basename(:DEB)
    end

    def common_deb_path
      common_package_path(:DEB)
    end

    def common_deb_possible_repo_urls
      distributions.find_all do |distro|
        distro[:package_format] == :DEB
      end.map do |distro|
        common_package_repo_url(distro)
      end.uniq
    end

    def common_rpm_version
      @config[:common][:rpm][:version]
    end

    def common_rpm_package_revision
      @config[:common][:rpm][:package_revision]
    end

    def common_rpm_basename
      common_package_basename(:RPM)
    end

    def common_rpm_path
      common_package_path(:RPM)
    end

    def common_rpm_possible_repo_urls
      distributions.find_all do |distro|
        distro[:package_format] == :RPM
      end.map do |distro|
        common_package_repo_url(distro)
      end.uniq
    end

    def common_package_basename(package_format)
      case package_format
      when :DEB
        "fullstaq-ruby-common_#{common_deb_version}-#{common_deb_package_revision}_all.deb"
      when :RPM
        "fullstaq-ruby-common-#{common_rpm_version}-#{common_rpm_package_revision}.noarch.rpm"
      else
        raise "Unsupported package format: #{package_format.inspect}"
      end
    end

    def common_package_path(package_format)
      "#{output_dir}/#{common_package_basename(package_format)}"
    end

    def common_package_repo_url(distro)
      basename = common_package_basename(distro[:package_format])
      case distro[:package_format]
      when :DEB
        "#{apt_repo_base_url}/#{basename}"
      when :RPM
        "#{yum_repo_base_url}/#{distro[:name]}/#{rpm_arch}/#{basename}"
      else
        raise "Unsupported package format: #{distro[:package_format].inspect}"
      end
    end


    def jemalloc_version
      @config[:jemalloc_version]
    end

    def jemalloc_source_basename
      "jemalloc-#{@config[:jemalloc_version]}.tar.bz2"
    end

    def jemalloc_source_url
      "https://github.com/jemalloc/jemalloc/releases/download/#{jemalloc_version}/#{jemalloc_source_basename}"
    end

    def jemalloc_source_path
      "#{cache_dir}/#{jemalloc_source_basename}"
    end

    def jemalloc_bin_path(distro)
      "#{output_dir}/jemalloc-bin-#{jemalloc_version}-#{distro[:name]}.tar.gz"
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

    def ruby_package_basename(package_version, distro, variant)
      case distro[:package_format]
      when :DEB
        "fullstaq-ruby-#{package_version[:id]}#{variant[:package_suffix]}_#{package_version[:package_revision]}-#{distro[:name]}_#{deb_arch}.deb"
      when :RPM
        "fullstaq-ruby-#{package_version[:id]}#{variant[:package_suffix]}-rev#{package_version[:package_revision]}-#{sanitize_distro_name_for_rpm(distro[:name])}.#{rpm_arch}.rpm"
      else
        raise "Unsupported package format: #{distro[:package_format].inspect}"
      end
    end

    def ruby_package_path(package_version, distro, variant)
      "#{output_dir}/#{ruby_package_basename(package_version, distro, variant)}"
    end

    def ruby_package_repo_url(package_version, distro, variant)
      basename = ruby_package_basename(package_version, distro, variant)
      case distro[:package_format]
      when :DEB
        "#{apt_repo_base_url}/#{basename}"
      when :RPM
        "#{yum_repo_base_url}/#{distro[:name]}/#{rpm_arch}/#{basename}"
      else
        raise "Unsupported package format: #{distro[:package_format].inspect}"
      end
    end


    def initialize_for_rake
      require 'rest-client'
    end

    def initialize_progress_tracking(rake_context)
      require 'paint'
      require 'paint/rgb_colors'
      require_relative 'progress_tracker'
      @progress_tracker = ProgressTracker.new
      @progress_tracker_pipe = IO.pipe
      @rake_context = rake_context
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

    def define_file_task(progress_category_or_entry, name:, id:, path:, deps: nil)
      if progress_category_or_entry.is_a?(ProgressTracker::Category)
        progress_stage = progress_category_or_entry.define_entry(name, id)
      else
        progress_stage = progress_category_or_entry.define_stage(name, id)
      end
      if deps
        task_spec = { path => deps }
      else
        task_spec = path
      end
      @rake_context.send(:file, task_spec) do
        progress_stage.track_work do
          yield(progress_stage)
        end
      end
    end

    def define_task(progress_category_or_entry, name:, id:, task:, deps: nil, desc: nil)
      if progress_category_or_entry.is_a?(ProgressTracker::Category)
        progress_stage = progress_category_or_entry.define_entry(name, id)
      else
        progress_stage = progress_category_or_entry.define_stage(name, id)
      end
      if deps
        task_spec = { task => deps }
      else
        task_spec = task
      end
      if desc
        @rake_context.send(:desc, desc)
      end
      @rake_context.send(:task, task_spec) do
        progress_stage.track_work do
          yield(progress_stage)
        end
      end
    end


    def should_try_download_packages_from_repo?
      getenv_boolean('DOWNLOAD_PACKAGES_FROM_REPO')
    end

    def check_which_packages_are_in_repo
      require 'concurrent'

      STDERR.puts "--> Checking which packages already exist in repositories"
      pool = Concurrent::FixedThreadPool.new(16)
      begin
        @packages_in_repo = {}
        promises = []

        promises.concat(check_whether_common_packages_are_in_repo(pool))
        promises.concat(check_whether_rbenv_packages_are_in_repo(pool))

        ruby_package_versions.each do |package_version|
          distributions.each do |distro|
            variants.each do |variant|
              promises << check_whether_ruby_package_is_in_repo(pool,
                package_version, distro, variant)
            end
          end
        end

        promises.each_with_index do |promise, i|
          basename, url, result = promise.value!
          # Basename may not be unique, but we only care whether there's
          # at least one existant URL for that basename.
          @packages_in_repo[basename] ||= result

          case result
          when true
            STDERR.puts Paint[sprintf("%03d/%03d | Exists   : %s",
              i + 1, promises.size, basename), :green]
            STDERR.puts "          Checked #{url}"
            STDERR.puts "          Will download it"
          when false
            STDERR.puts Paint[sprintf("%03d/%03d | Not found: %s",
              i + 1, promises.size, basename), :yellow, :bold]
            STDERR.puts "          Checked #{url}"
            STDERR.puts "          Will build it"
          else
            exception = result
            STDERR.puts Paint[sprintf("%03d/%03d | Error    : %s",
              i + 1, promises.size, basename), :red, :bold]
            STDERR.puts "          Checked #{url}"
            STDERR.puts "       => #{exception} (#{exception.class})"
            STDERR.puts "          #{exception.backtrace.join("\n          ")}"
          end
        end

        if promises.any? { |p| p.value![2].is_a?(Exception) }
          abort
        end
      ensure
        pool.shutdown
        pool.wait_for_termination
      end
    end

    def package_exists_in_repo?(package_basename)
      if @packages_in_repo.key?(package_basename)
        @packages_in_repo[package_basename]
      else
        raise "BUG: unknown whether #{package_basename} exists in repository."
      end
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
        sh 'curl', '-fSLRo', output, url
      elsif has_wget?
        sh 'wget', '-O', output, url
      else
        log "*** ERROR: Cannot download #{url}: no curl or wget installed"
        abort
      end
    end

    def download_from_one_of(urls, output)
      urls.each_with_index do |url, i|
        log "--> Checking whether #{url} exists"
        begin
          RestClient.head(url)
        rescue RestClient::NotFound
          if i == urls.size - 1
            log "no"
          else
            log "no; trying next URL"
          end
        else
          log "yes"
          return download(url, output)
        end

        log "*** ERROR: none of the attempted URLs exist"
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

    def check_whether_common_packages_are_in_repo(executor)
      candidates = distributions.map do |distro|
        basename = common_package_basename(distro[:package_format])
        url = common_package_repo_url(distro)
        [basename, url]
      end
      candidates.uniq!
      candidates.map do |basename, url|
        Concurrent::Promises.future_on(executor) do
          check_whether_package_exists(basename, url)
        end
      end
    end

    def check_whether_rbenv_packages_are_in_repo(executor)
      candidates = distributions.map do |distro|
        basename = rbenv_package_basename(distro[:package_format])
        url = rbenv_package_repo_url(distro)
        [basename, url]
      end
      candidates.uniq!
      candidates.map do |basename, url|
        Concurrent::Promises.future_on(executor) do
          check_whether_package_exists(basename, url)
        end
      end
    end

    def check_whether_ruby_package_is_in_repo(executor, package_version, distro, variant)
      Concurrent::Promises.future_on(executor) do
        basename = ruby_package_basename(package_version, distro, variant)
        url = ruby_package_repo_url(package_version, distro, variant)
        check_whether_package_exists(basename, url)
      end
    end

    def check_whether_package_exists(basename, url)
      begin
        RestClient.head(url)
      rescue RestClient::NotFound, RestClient::Unauthorized
        # Bintray returns 401 Unauthorized if the package was uploaded but
        # not yet published. We treat that as not found.
        [basename, url, false]
      rescue => e
        [basename, url, e]
      else
        [basename, url, true]
      end
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

    def getenv_boolean(name)
      value = ENV[name].to_s.downcase
      ['true', 't', 'yes', 'y', '1', 'on'].include?(value)
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
