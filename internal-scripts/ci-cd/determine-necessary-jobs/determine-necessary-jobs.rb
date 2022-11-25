#!/usr/bin/env ruby
require 'set'
require 'json'
require 'net/http'
require_relative '../../../lib/general_support'
require_relative '../../../lib/shell_scripting_support'
require_relative '../../../lib/ci_workflow_support'

class App
  include GeneralSupport
  include ShellScriptingSupport
  include CiWorkflowSupport

  GHCR_AUTH_URL = 'https://ghcr.io/token?scope=repository:fullstaq-ruby/server-edition-ci-images:pull'

  def initialize(existing_artifacts_list_path)
    require_envvar 'GITHUB_ACTOR'
    require_envvar 'GITHUB_TOKEN'
    authenticate_container_registry
    load_config
    @jobs_to_be_run = []
    @jobs_to_be_skipped = []
    @artifacts = File.open(existing_artifacts_list_path, 'r:utf-8') do |f|
      Set.new(f.read.split("\n"))
    end
  end

  def execute
    docker_images.each do |image|
      determine_necessary_job("Build Docker image #{image[:id]}") do
        docker_image_absent_in_registry?(image[:name], image[:tag]) &&
          artifact_absent?(docker_image_artifact_name(image[:id]))
      end
    end
    docker_images.each do |image|
      determine_necessary_job("Use locally-built Docker image #{image[:id]}") do
        docker_image_absent_in_registry?(image[:name], image[:tag])
      end
    end


    ruby_source_versions.each do |ruby_version|
      determine_necessary_job("Download Ruby source #{ruby_version}") do
        artifact_absent?(ruby_source_artifact_name(ruby_version))
      end
    end

    determine_necessary_job('Download Rbenv source') do
      artifact_absent?(rbenv_source_artifact_name)
    end


    distributions.each do |distribution|
      determine_necessary_job("Build Jemalloc [#{distribution[:name]}]") do
        artifact_absent?("jemalloc-bin-#{distribution[:name]}")
      end
    end


    determine_necessary_job('Install gem bundle') do
      artifact_absent?('gem-bundle')
    end
    determine_necessary_job('Build common DEB') do
      artifact_absent?(common_deb_artifact_name)
    end
    determine_necessary_job('Build common RPM') do
      artifact_absent?(common_rpm_artifact_name)
    end

    determine_necessary_job('Build Rbenv DEB') do
      artifact_absent?(rbenv_deb_artifact_name)
    end
    determine_necessary_job('Build Rbenv RPM') do
      artifact_absent?(rbenv_rpm_artifact_name)
    end


    distributions.each do |distribution|
      ruby_package_versions.each do |ruby_package_version|
        variants.each do |variant|
          determine_necessary_job("Build Ruby [#{distribution[:name]}/#{ruby_package_version[:id]}/#{variant[:name]}]") do
            artifact_absent?(ruby_package_artifact_name(ruby_package_version, distribution, variant))
          end
        end
      end
    end


    distributions.each do |distribution|
      ruby_package_versions.each do |ruby_package_version|
        variants.each do |variant|
          determine_necessary_job("Test against test repo [#{distribution[:name]}/#{ruby_package_version[:id]}/#{variant[:name]}]") do
            artifact_absent?("tested-against-test-#{distribution[:name]}_#{ruby_package_version[:id]}_#{variant[:name]}")
          end
        end
      end
    end

    distributions.each do |distribution|
      ruby_package_versions.each do |ruby_package_version|
        variants.each do |variant|
          determine_necessary_job("Test against production repo [#{distribution[:name]}/#{ruby_package_version[:id]}/#{variant[:name]}]") do
            artifact_absent?("tested-against-production-#{distribution[:name]}_#{ruby_package_version[:id]}_#{variant[:name]}")
          end
        end
      end
    end


    report_results
  end

private
  def authenticate_container_registry
    response = http_get(GHCR_AUTH_URL, username: ENV['GITHUB_ACTOR'], password: ENV['GITHUB_TOKEN'])
    if response.code != '200'
      abort "*** Error requesting #{GHCR_AUTH_URL}: HTTP response #{response.code}"
    end

    doc = JSON.parse(response.body)
    @container_registry_token = doc['token']
  end

  def determine_necessary_job(job_description)
    if yield
      @jobs_to_be_run << job_description
    else
      @jobs_to_be_skipped << job_description
    end
  end

  def artifact_absent?(name)
    !@artifacts.include?(name)
  end

  def docker_image_absent_in_registry?(image_name, image_tag)
    image_name_without_host = image_name.sub(/^ghcr.io\//, '')
    url = "https://ghcr.io/v2/#{image_name_without_host}/manifests/#{image_tag}"
    response = http_get(url, bearer_token: @container_registry_token)
    if response.code == '200'
      false
    elsif response.code == '404'
      true
    else
      abort "*** Error requesting #{url}: HTTP response #{response.code}"
    end
  end

  def http_get(url, username: nil, password: nil, bearer_token: nil)
    uri = URI.parse(url)
    request = Net::HTTP::Get.new(uri)
    if username
      request.basic_auth(username, password)
    elsif bearer_token
      request['Authorization'] = "Bearer #{bearer_token}"
    end

    redirect_limit = 10
    result = nil

    while result.nil?
      if redirect_limit == 0
        abort "*** Error requesting #{url}: too many redirects"
      end

      begin
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.port == 443) do |http|
          http.request(request)
        end
      rescue SystemCallError => e
        abort "*** Error requesting #{url}: #{e}"
      end

      if response.is_a?(Net::HTTPRedirection)
        redirect_limit = redirect_limit - 1
        uri = URI.parse(response['location'])
      else
        result = response
      end
    end

    response
  end

  def run_command(command, env)
    pid = Process.spawn(env, command)
    Process.waitpid(pid)
    return $?.exitstatus == 0
  end

  def report_results
    print_ci_output_variable(@jobs_to_be_run)
    puts

    puts "### These jobs will be run:"
    puts
    print_job_descriptions(@jobs_to_be_run)
    puts

    puts "### These jobs will be skipped:"
    puts
    print_job_descriptions(@jobs_to_be_skipped)
  end

  def print_job_descriptions(job_descriptions)
    if job_descriptions.empty?
      puts "(none)"
    else
      job_descriptions.each do |desc|
        puts desc
      end
    end
  end

  def print_ci_output_variable(job_descriptions)
    value = job_descriptions.join(';')
    File.open(ENV['GITHUB_OUTPUT'] || '/dev/stdout', 'a') do |f|
      f.puts "necessary_jobs=;#{value};"
    end
  end
end

App.new(ARGV[0] || 'artifacts.txt').execute
