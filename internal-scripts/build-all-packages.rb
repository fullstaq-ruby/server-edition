#!/usr/bin/env ruby
# This is a Rakefile, to be run in Drake for parallelization.

require_relative '../lib/build_all_packages_support'

Support.initialize_progress_tracking
Support.load_config


### Top-level tasks ###

desc('Test all packages')
task 'default' => 'test'

desc('Build all packages')
task('build' => [Support.rbenv_deb_path, Support.rbenv_rpm_path,
  Support.common_deb_path, Support.common_rpm_path])

desc('Test all packages')
task('test' => [Support.rbenv_deb_path, Support.rbenv_rpm_path,
  Support.common_deb_path, Support.common_rpm_path])

desc('Test all public repository packages')
task('repotest')

### Lifecycle tasks ###

task '_start' do
  Support.start_progress_tracking
  at_exit { Support.stop_progress_tracking }
end


### Sources ###

Support.define_progress_category('Sources') do |progress_category|
  # jemalloc-XXX.tar.bz2
  progress_category.define_entry('Jemalloc', 'sources:jemalloc') do |progress_entry|
    file(Support.jemalloc_source_path) do
      progress_entry.track_work do
        Support.download(Support.jemalloc_source_url,
          Support.jemalloc_source_path)
      end
    end
  end

  # ruby-XXX.tar.gz
  Support.ruby_source_versions.each do |ruby_source_version|
    progress_entry = progress_category.define_entry("Ruby #{ruby_source_version}",
      "sources:ruby-#{ruby_source_version}")
    ruby_source_path = Support.ruby_source_path(ruby_source_version)

    file(ruby_source_path) do
      progress_entry.track_work do
        Support.download(Support.ruby_source_url(ruby_source_version),
          ruby_source_path)
      end
    end
  end
end


### fullstaq-ruby-common ###

Support.define_progress_category('Common') do |progress_category|
  desc 'Build all fullstaq-ruby-common packages'
  task('build:common' => [Support.common_deb_path, Support.common_rpm_path])

  desc('Build fullstaq-ruby-common DEB')
  task('build:common:deb' => Support.common_deb_path)

  desc('Build fullstaq-ruby-common RPM')
  task('build:common:rpm' => Support.common_rpm_path)

  # fullstaq-ruby-common_XXX_all.deb
  progress_category.define_entry('DEB', 'common:deb') do |progress_entry|
    file(Support.common_deb_path) do
      progress_entry.track_work do
        Support.sh './build-common-deb',
          '-o', Support.common_deb_path,
          '-r', Support.config[:common][:deb][:package_revision].to_s
      end
    end
  end

  # fullstaq-ruby-common-XXX.noarch.rpm
  progress_category.define_entry('RPM', 'common:rpm') do |progress_entry|
    file(Support.common_rpm_path) do
      progress_entry.track_work do
        Support.sh './build-common-rpm',
          '-o', Support.common_rpm_path,
          '-r', Support.config[:common][:rpm][:package_revision].to_s
      end
    end
  end
end


### Rbenv ###

Support.define_progress_category('Rbenv') do |progress_category|
  desc 'Build Rbenv all packages'
  task('build:rbenv' => [Support.rbenv_deb_path, Support.rbenv_rpm_path])

  desc('Build Rbenv DEB')
  task('build:rbenv:deb' => Support.rbenv_deb_path)

  desc('Build Rbenv RPM')
  task('build:rbenv:rpm' => Support.rbenv_rpm_path)

  # fullstaq-rbenv_XXX_all.deb
  progress_category.define_entry('DEB', 'rbenv:deb') do |progress_entry|
    file(Support.rbenv_deb_path) do
      progress_entry.track_work do
        begin
          Support.sh './build-rbenv-deb',
            '-s', Support.rbenv_source_path,
            '-o', Support.rbenv_deb_path,
            '-r', Support.config[:rbenv][:package_revision].to_s
        rescue Exception => e
          Support.delete_empty_file(Support.rbenv_deb_path)
          raise e
        end
      end
    end
  end

  # fullstaq-rbenv-XXX.noarch.rpm
  progress_category.define_entry('RPM', 'rbenv:rpm') do |progress_entry|
    file(Support.rbenv_rpm_path) do
      progress_entry.track_work do
        begin
          Support.sh './build-rbenv-rpm',
            '-s', Support.rbenv_source_path,
            '-o', Support.rbenv_rpm_path,
            '-r', Support.config[:rbenv][:package_revision].to_s
        rescue Exception => e
          Support.delete_empty_file(Support.rbenv_rpm_path)
          raise e
        end
      end
    end
  end
end


### Jemalloc ###

Support.define_progress_category('Jemalloc') do |progress_category|
  Support.distributions.each do |distro|
    progress_entry = progress_category.define_entry(distro[:name],
      "jemalloc-bin:#{distro[:name]}")
    jemalloc_bin_path = Support.jemalloc_bin_path(distro)

    # jemalloc-bin-XXX-DISTRO.tar.gz
    file(jemalloc_bin_path => [Support.jemalloc_source_path]) do
      progress_entry.track_work do
        cache_dir = "#{Support.cache_dir}/jemalloc-#{distro[:name]}"
        Support.sh('mkdir', '-p', cache_dir)
        begin
          Support.sh './build-jemalloc',
            '-n', distro[:name],
            '-s', Support.jemalloc_source_path,
            '-o', jemalloc_bin_path,
            '-c', cache_dir
        rescue Exception => e
          Support.delete_empty_file(jemalloc_bin_path)
          raise e
        end
      end
    end
  end
end


### Ruby ###

Support.ruby_package_versions.each do |ruby_package_version|
  desc("Build all packages for Ruby #{ruby_package_version[:id]}")
  task("build:ruby-#{ruby_package_version[:id]}")

  desc("Test all packages for Ruby #{ruby_package_version[:id]}")
  task("test:ruby-#{ruby_package_version[:id]}")

  desc("Test all public repository packages for Ruby #{ruby_package_version[:id]}")
  task("repotest:ruby-#{ruby_package_version[:id]}")
end

Support.ruby_package_versions.each do |ruby_package_version|
  progress_category = Support.define_progress_category("Ruby #{ruby_package_version[:id]}")

  Support.distributions.each do |distro|
    Support.variants.each do |variant|
      progress_entry = progress_category.define_entry("#{distro[:package_format]} #{distro[:name]} #{variant[:name]}", nil)
      ruby_package_path = Support.ruby_package_path(ruby_package_version, distro, variant)
      ruby_bin_path = Support.ruby_bin_path(ruby_package_version, distro, variant)
      ruby_source_path = Support.ruby_source_path_for_package_version(ruby_package_version)
      rbenv_package_path = Support.rbenv_package_path(distro[:package_format])
      common_package_path = Support.common_package_path(distro[:package_format])
      jemalloc_bin_path = Support.jemalloc_bin_path(distro)

      task('build' => ruby_package_path)
      task("build:ruby-#{ruby_package_version[:id]}" => ruby_package_path)

      desc("Build #{distro[:package_format]} for Ruby #{ruby_package_version[:id]}, for #{distro[:name]}, variant #{variant[:name]}")
      task("build:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}" => ruby_package_path)

      task('test' => "test:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}")
      task("test:ruby-#{ruby_package_version[:id]}" => "test:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}")

      task('repotest' => "repotest:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}")
      task("repotest:ruby-#{ruby_package_version[:id]}" => "repotest:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}")


      # ruby-bin-XXX-VARIANT-DISTRO.tar.gz
      progress_entry.define_stage('Build', "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:build") do |progress_stage|
        file(ruby_bin_path => [ruby_source_path, jemalloc_bin_path]) do
          progress_stage.track_work do
            cache_dir = "#{Support.cache_dir}/ruby-#{ruby_package_version[:id]}-#{distro[:name]}-#{variant[:name]}"

            case variant[:name]
            when 'normal'
              extra_args = []
            when 'jemalloc'
              extra_args = ['-m', jemalloc_bin_path]
            when 'malloctrim'
              extra_args = ['-t']
            else
              raise "BUG: unsupported variant #{variant[:name].inspect}"
            end

            Support.sh('mkdir', '-p', cache_dir)
            begin
              Support.sh(
                './build-ruby',
                '-n', distro[:name],
                '-s', ruby_source_path,
                '-v', ruby_package_version[:id].to_s,
                '-o', ruby_bin_path,
                '-c', cache_dir,
                *extra_args
              )
            rescue Exception => e
              Support.delete_empty_file(ruby_bin_path)
              raise e
            end
          end
        end
      end

      # fullstaq-ruby_XXX-YYY_ARCH.deb
      # fullstaq-ruby-XXX-YYY.ARCH.rpm
      progress_entry.define_stage('Package', "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:package") do |progress_stage|
        file(ruby_package_path => [ruby_bin_path]) do
          progress_stage.track_work do
            begin
              case distro[:package_format]
              when :DEB
                Support.sh './build-ruby-deb',
                  '-b', ruby_bin_path,
                  '-o', ruby_package_path,
                  '-r', ruby_package_version[:package_revision].to_s
              when :RPM
                Support.sh './build-ruby-rpm',
                  '-b', ruby_bin_path,
                  '-o', ruby_package_path,
                  '-r', ruby_package_version[:package_revision].to_s
              else
                raise "BUG: unsupported package format: #{distro[:package_format].inspect}"
              end
            rescue Exception => e
              Support.delete_empty_file(ruby_package_path)
              raise e
            end
          end
        end
      end

      progress_entry.define_stage('Test', "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:test") do |progress_stage|
        desc("Test #{distro[:package_format]} for Ruby #{ruby_package_version[:id]}, for #{distro[:name]}, variant #{variant[:name]}")
        deps = [ruby_package_path, rbenv_package_path, common_package_path]
        task("test:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}" => deps) do
          progress_stage.track_work do
            case distro[:package_format]
            when :DEB
              Support.sh './test-debs',
                '-r', ruby_package_path,
                '-b', rbenv_package_path,
                '-c', common_package_path,
                '-i', Support.determine_test_image_for(distro),
                '-v', variant[:name]
            when :RPM
              Support.sh './test-rpms',
                '-r', ruby_package_path,
                '-b', rbenv_package_path,
                '-c', common_package_path,
                '-i', Support.determine_test_image_for(distro),
                '-v', variant[:name]
            else
              raise "BUG: unsupported package format: #{distro[:package_format].inspect}"
            end
          end
        end
      end

      progress_entry.define_stage('RepoTest', "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:repotest") do |progress_stage|
        desc("Public repo test #{distro[:package_format]} for Ruby #{ruby_package_version[:id]}, for #{distro[:name]}, variant #{variant[:name]}")
        task("repotest:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}") do
          progress_stage.track_work do
            case distro[:package_format]
            when :DEB
              Support.sh './test-debs',
                '-S', 'https://apt.fullstaqruby.org',
                '-i', Support.determine_test_image_for(distro),
                '-v', variant[:name],
                '-d', distro[:name],
                '-n', "#{ruby_package_version[:id]}#{variant[:package_suffix]}"
            when :RPM
              Support.sh './test-rpms',
                '-S', "https://yum.fullstaqruby.org/#{distro[:name]}",
                '-i', Support.determine_test_image_for(distro),
                '-v', variant[:name],
                '-n', "#{ruby_package_version[:id]}#{variant[:package_suffix]}"
            else
              raise "BUG: unsupported package format: #{distro[:package_format].inspect}"
            end
          end
        end
      end
    end
  end
end
