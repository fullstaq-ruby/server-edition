#!/usr/bin/env ruby
require 'erb'
require 'json'
require 'yaml'
require_relative '../lib/build_all_packages_support'

SELFDIR = File.absolute_path(File.dirname(__FILE__))
TEMPLATE_PATH = File.absolute_path("#{SELFDIR}/../.github/workflows/ci-cd.yml.erb")
DEFAULT_OUTPUT_PATH = File.absolute_path("#{SELFDIR}/../.github/workflows/ci-cd.yml")

Support.load_config

Support.class_eval do
  def self.editing_warning_comment
    "# WARNING: DO NOT EDIT THIS FILE!!!\n" \
    "#\n" \
    "# This file is autogenerated from .github/workflows/ci-cd.yml.erb\n" \
    "# by ./internal-scripts/generate-ci-cd-yaml.rb.\n" \
    "# Please edit the .erb file instead, then regenerate YAML\n" \
    "# by running that script.\n" \
    "#\n" \
    "# TIP: run this on your development machine to ensure generate-ci-cd-yaml.rb\n" \
    "# is run automatically as a Git pre-commit hook:\n" \
    "#\n" \
    "#   git config core.hooksPath .githooks"
  end

  def self.indentyaml(object)
    # Change symbols to strings
    object = JSON.parse(JSON.dump(object))

    str = YAML.dump(object)
    str.sub!(/^---\n/, '')

    indent = ' ' * 10
    lines = str.split("\n")
    lines.map! { |line| indent + line }
    "\n" + lines.join("\n")
  end

  def self.docker_images
    Dir["#{SELFDIR}/../environments/*"].find_all do |path|
      File.exist?("#{path}/Dockerfile")
    end.sort.map do |path|
      id = File.basename(path)
      {
        name: "fullstaq/ruby-build-env-#{id}",
        id: id,
        tag: read_single_value_file("#{path}/image_tag")
      }
    end
  end

  def self.ruby_package_artifact_names
    result = []
    ruby_package_versions.each do |ruby_package_version|
      distributions.each do |distribution|
        variants.each do |variant|
          result << "ruby-pkg_#{ruby_package_version[:id]}_#{distribution[:name]}_#{variant[:name]}"
        end
      end
    end
    result
  end

  def self.unindent(amount, &block)
    indentation = /^#{' ' * amount}/
    lines = capture(&block).split("\n")
    lines.map! { |l| l.sub(indentation, '') }
    @erb_out << lines.join("\n")
  end

  def self.capture
    pos = @erb_out.size
    yield
    @erb_out.slice!(pos..@erb_out.size)
  end

  # A single-value file is a file such as environments/ubuntu-18.04/image_tag.
  # It contains exactly 1 line of usable value, and may optionally contain
  # comments that start with '#', which are ignored.
  def self.read_single_value_file(path)
    contents = File.read(path, mode: 'r:utf-8')
    contents.split("\n").grep_v(/^#/).first.strip
  end


  template_src = File.read(TEMPLATE_PATH, mode: 'r:utf-8')
  erb = ERB.new(template_src, nil, '-', '@erb_out')
  erb.location = TEMPLATE_PATH
  result = erb.result(binding)

  if ARGV[0] == '-'
    puts result
  elsif ARGV[0]
    File.open(ARGV[0], 'w:utf-8') do |f|
      f.write(result)
    end
  else
    File.open(DEFAULT_OUTPUT_PATH, 'w:utf-8') do |f|
      f.write(result)
    end
  end
end
