#!/usr/bin/env ruby
# Print all minor Ruby versions for which all of the following is true:
#
# - It's packaged by both the previous Fullstaq Ruby release
#   as well as the current one.
# - Its `full_version` has changed compared to the previous release.
# - The package revision has not been bumped.
require 'yaml'

CURRENT_CONFIG_PATH = ARGV[0]
LATEST_RELEASE_CONFIG_PATH = ARGV[1]

def load_current_config
  File.open(CURRENT_CONFIG_PATH, 'r:utf-8') do |f|
    YAML.safe_load(f.read, filename: CURRENT_CONFIG_PATH)
  end
end

def load_latest_release_config
  File.open(LATEST_RELEASE_CONFIG_PATH, 'r:utf-8') do |f|
    YAML.safe_load(f.read, filename: LATEST_RELEASE_CONFIG_PATH)
  end
end

def find_minor_version_package(config, minor_version_package)
  config['ruby']['minor_version_packages'].find do |candidate|
    candidate['minor_version'] == minor_version_package['minor_version']
  end
end

def package_revision_needs_bumping?(current, latest)
  current['full_version'] != latest['full_version'] && \
    current['package_revision'] == latest['package_revision']
end

def main
  current_config = load_current_config
  latest_release_config = load_latest_release_config

  current_config['ruby']['minor_version_packages'].each do |current_minor_version_package|
    latest_release_minor_version_package = find_minor_version_package(
      latest_release_config, current_minor_version_package)
    next if latest_release_minor_version_package.nil?

    if package_revision_needs_bumping?(current_minor_version_package, latest_release_minor_version_package)
      puts "minor_version == #{current_minor_version_package['minor_version']}"
    end
  end
end

main
