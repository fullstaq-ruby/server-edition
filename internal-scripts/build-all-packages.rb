#!/usr/bin/env ruby
# This is a Rakefile, to be run in Drake for parallelization.

require_relative '../lib/build_all_packages_support'

Support.initialize_for_rake
Support.initialize_progress_tracking(self)
Support.load_config
Support.checkout_rbenv_if_necessary
Support.verify_rbenv_version_in_config
if Support.should_try_download_packages_from_repo?
  Support.check_which_packages_are_in_repo
end
puts


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
  Support.define_file_task(progress_category,
    name: 'Jemalloc',
    id: 'sources:jemalloc',
    path: Support.jemalloc_source_path) \
  do |_|
    Support.download(Support.jemalloc_source_url,
      Support.jemalloc_source_path)
  end

  # ruby-XXX.tar.gz
  Support.ruby_source_versions.each do |ruby_source_version|
    ruby_source_path = Support.ruby_source_path(ruby_source_version)

    Support.define_file_task(progress_category,
      name: "Ruby #{ruby_source_version}",
      id: "sources:ruby-#{ruby_source_version}",
      path: ruby_source_path) \
    do |_|
      Support.download(Support.ruby_source_url(ruby_source_version),
          ruby_source_path)
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
  Support.define_file_task(progress_category,
    name: 'DEB',
    id: 'common:deb',
    path: Support.common_deb_path) \
  do |_|
    if Support.should_try_download_packages_from_repo? &&
       Support.package_exists_in_repo?(Support.common_deb_basename)

      Support.download_from_one_of(Support.common_deb_possible_repo_urls,
        Support.common_deb_path)
    else
      Support.sh './build-common-deb',
        '-o', Support.common_deb_path,
        '-v', Support.config[:common][:deb][:version].to_s,
        '-r', Support.config[:common][:deb][:package_revision].to_s
    end
  end

  # fullstaq-ruby-common-XXX.noarch.rpm
  Support.define_file_task(progress_category,
    name: 'RPM',
    id: 'common:rpm',
    path: Support.common_rpm_path) \
  do |_|
    if Support.should_try_download_packages_from_repo? &&
       Support.package_exists_in_repo?(Support.common_rpm_basename)

      Support.download_from_one_of(Support.common_rpm_possible_repo_urls,
        Support.common_rpm_path)
    else
      Support.sh './build-common-rpm',
        '-o', Support.common_rpm_path,
        '-v', Support.config[:common][:rpm][:version].to_s,
        '-r', Support.config[:common][:rpm][:package_revision].to_s
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
  Support.define_file_task(progress_category,
    name: 'DEB',
    id: 'rbenv:deb',
    path: Support.rbenv_deb_path) \
  do |_|
    if Support.should_try_download_packages_from_repo? &&
       Support.package_exists_in_repo?(Support.rbenv_deb_basename)

      Support.download_from_one_of(Support.rbenv_deb_possible_repo_urls,
        Support.rbenv_deb_path)
    else
      Support.sh './build-rbenv-deb',
        '-s', Support.rbenv_source_path,
        '-o', Support.rbenv_deb_path,
        '-r', Support.config[:rbenv][:package_revision].to_s
    end
  end

  # fullstaq-rbenv-XXX.noarch.rpm
  Support.define_file_task(progress_category,
    name: 'RPM',
    id: 'rbenv:rpm',
    path: Support.rbenv_rpm_path) \
  do |_|
    if Support.should_try_download_packages_from_repo? &&
       Support.package_exists_in_repo?(Support.rbenv_rpm_basename)

      Support.download_from_one_of(Support.rbenv_rpm_possible_repo_urls,
        Support.rbenv_rpm_path)
    else
      Support.sh './build-rbenv-rpm',
        '-s', Support.rbenv_source_path,
        '-o', Support.rbenv_rpm_path,
        '-r', Support.config[:rbenv][:package_revision].to_s
    end
  end
end


### Jemalloc ###

Support.define_progress_category('Jemalloc') do |progress_category|
  Support.distributions.each do |distro|
    jemalloc_bin_path = Support.jemalloc_bin_path(distro)

    # jemalloc-bin-XXX-DISTRO.tar.gz
    Support.define_file_task(progress_category,
      name: distro[:name],
      id: "jemalloc-bin:#{distro[:name]}",
      path: jemalloc_bin_path,
      deps: [Support.jemalloc_source_path]) \
    do |_|
      cache_dir = "#{Support.cache_dir}/jemalloc-#{distro[:name]}"
      Support.sh('mkdir', '-p', cache_dir)
      Support.sh './build-jemalloc',
        '-n', distro[:name],
        '-s', Support.jemalloc_source_path,
        '-o', jemalloc_bin_path,
        '-c', cache_dir
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
      ruby_package_basename = Support.ruby_package_basename(ruby_package_version, distro, variant)
      ruby_package_path = Support.ruby_package_path(ruby_package_version, distro, variant)
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


      if Support.should_try_download_packages_from_repo? &&
         Support.package_exists_in_repo?(ruby_package_basename)

        # fullstaq-ruby_XXX-YYY_ARCH.deb
        # fullstaq-ruby-XXX-YYY.ARCH.rpm
        Support.define_file_task(progress_entry,
          name: 'Package',
          id: "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:package",
          path: ruby_package_path) \
        do |_|
          url = Support.ruby_package_repo_url(ruby_package_version, distro, variant)
          Support.download(url, ruby_package_path)
        end
      else
        ruby_bin_path = Support.ruby_bin_path(ruby_package_version, distro, variant)

        # ruby-bin-XXX-VARIANT-DISTRO.tar.gz
        Support.define_file_task(progress_entry,
          name: 'Build',
          id: "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:build",
          path: ruby_bin_path,
          deps: [ruby_source_path, jemalloc_bin_path]) \
        do |_|
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
          Support.sh(
            './build-ruby',
            '-n', distro[:name],
            '-s', ruby_source_path,
            '-v', ruby_package_version[:id].to_s,
            '-o', ruby_bin_path,
            '-c', cache_dir,
            *extra_args
          )
        end

        # fullstaq-ruby_XXX-YYY_ARCH.deb
        # fullstaq-ruby-XXX-YYY.ARCH.rpm
        Support.define_file_task(progress_entry,
          name: 'Package',
          id: "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:package",
          path: ruby_package_path,
          deps: [ruby_bin_path]) \
        do |_|
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
        end
      end

      Support.define_task(progress_entry,
        name: 'Test',
        id: "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:test",
        desc: "Test #{distro[:package_format]} for Ruby #{ruby_package_version[:id]}, for #{distro[:name]}, variant #{variant[:name]}",
        task: "test:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}",
        deps: [ruby_package_path, rbenv_package_path, common_package_path]) \
      do |_|
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

      Support.define_task(progress_entry,
        name: 'RepoTest',
        id: "ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}:repotest",
        desc: "Public repo test #{distro[:package_format]} for Ruby #{ruby_package_version[:id]}, for #{distro[:name]}, variant #{variant[:name]}",
        task: "repotest:ruby-#{ruby_package_version[:id]}:#{distro[:name]}:#{variant[:name]}") \
      do |_|
        case distro[:package_format]
        when :DEB
          Support.sh './test-debs',
            '-S', Support.apt_repo_base_url,
            '-i', Support.determine_test_image_for(distro),
            '-v', variant[:name],
            '-d', distro[:name],
            '-n', "#{ruby_package_version[:id]}#{variant[:package_suffix]}"
        when :RPM
          Support.sh './test-rpms',
            '-S', "#{Support.yum_repo_base_url}/#{distro[:name]}",
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
