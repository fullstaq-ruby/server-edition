#!/usr/bin/env ruby
require 'erb'
require_relative '../lib/build_all_packages_support'
require_relative '../lib/general_support'
require_relative '../lib/ci_workflow_support'

module CiCdYamlGenerationApp
  SELFDIR = File.absolute_path(File.dirname(__FILE__))
  ROOT = File.absolute_path("#{SELFDIR}/..")
  WORKFLOWS_SUBPATH = ".github/workflows"

  extend Support
  extend GeneralSupport
  extend CiWorkflowSupport

  def self.generate_yaml_file_from_template(name)
    input_path  = "#{ROOT}/#{WORKFLOWS_SUBPATH}/#{name}.yml.erb"
    output_path = "#{ROOT}/#{WORKFLOWS_SUBPATH}/#{name}.yml"
    puts "Regenerating #{WORKFLOWS_SUBPATH}/#{name}.yml"

    template_src = File.read(input_path, mode: 'r:utf-8')
    erb = ERB.new(template_src, nil, '-', '@erb_out')
    erb.location = input_path
    result = erb.result(binding)

    File.open(output_path, 'w:utf-8') do |f|
      f.write(result)
    end
  end

  load_config
  generate_yaml_file_from_template('ci-cd-main')
  generate_yaml_file_from_template('ci-cd-build-packages')
  generate_yaml_file_from_template('ci-cd-publish-test-test')
  generate_yaml_file_from_template('ci-cd-publish-test-production')
end
