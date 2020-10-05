#!/usr/bin/env ruby
require 'erb'
require_relative '../lib/build_all_packages_support'
require_relative '../lib/ci_workflow_support'

module CiCdYamlGenerationApp
  SELFDIR = File.absolute_path(File.dirname(__FILE__))
  TEMPLATE_PATH = File.absolute_path("#{SELFDIR}/../.github/workflows/ci-cd.yml.erb")
  DEFAULT_OUTPUT_PATH = File.absolute_path("#{SELFDIR}/../.github/workflows/ci-cd.yml")

  extend Support
  extend CiWorkflowSupport

  load_config

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
