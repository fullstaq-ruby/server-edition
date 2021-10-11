#!/usr/bin/env ruby
require 'erb'
require_relative '../lib/general_support'
require_relative '../lib/ci_workflow_support'

class TemplateContext
  include GeneralSupport
  include CiWorkflowSupport

  def get_binding
    binding
  end
end

class CiCdYamlGenerationApp
  ROOT = GeneralSupport::ROOT
  WORKFLOWS_SUBPATH = ".github/workflows"

  include CiWorkflowSupport

  def main
    load_config

    remove_yaml_files('ci-cd-build-packages*')

    generate_yaml_file_from_template(template_name: 'ci-cd-main')
    distribution_buckets.each_with_index do |distributions, i|
      generate_yaml_file_from_template(
        template_name: 'ci-cd-build-packages',
        output_name: "ci-cd-build-packages-#{i + 1}",
        part_number: i + 1,
        distributions: distributions,
        total_distribution_buckets_num: distribution_buckets.size)
    end
    generate_yaml_file_from_template(template_name: 'ci-cd-publish-test-test')
    generate_yaml_file_from_template(template_name: 'ci-cd-publish-test-production')
  end

private
  def remove_yaml_files(pattern)
    Dir["#{ROOT}/#{WORKFLOWS_SUBPATH}/#{pattern}.yml"].each do |path|
      puts "Removing #{WORKFLOWS_SUBPATH}/#{File.basename(path)}"
      File.unlink(path)
    end
  end

  def generate_yaml_file_from_template(template_name:, output_name: nil, **vars)
    input_path  = "#{ROOT}/#{WORKFLOWS_SUBPATH}/#{template_name}.yml.erb"
    output_path = "#{ROOT}/#{WORKFLOWS_SUBPATH}/#{output_name || template_name}.yml"
    puts "Regenerating #{WORKFLOWS_SUBPATH}/#{output_name || template_name}.yml"

    template_src = File.read(input_path, mode: 'r:utf-8')
    erb = ERB.new(template_src, nil, '-', '@erb_out')
    erb.location = input_path

    context = TemplateContext.new
    vars.each_pair do |name, value|
      context.define_singleton_method(name) do
        value
      end
    end
    result = erb.result(context.get_binding)

    File.open(output_path, 'w:utf-8') do |f|
      f.write(result)
    end
  end
end

CiCdYamlGenerationApp.new.main
