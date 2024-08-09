#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../../lib/shell_scripting_support'
require 'net/http'
require 'net/https'

class RestartWebServer
  include ShellScriptingSupport

  # There's only one web server, so no need to call yum.fullstaqruby.org
  RESTART_WEB_SERVER_API_URL = 'https://apt.fullstaqruby.org/admin/restart_web_server'
  LATEST_REPO_QUERY_TIMESTAMP_URL = 'https://apt.fullstaqruby.org/admin/repo_query_time'

  TIMEOUT_SECS = 60

  class QueryError < StandardError; end

  def main
    require_envvar('ID_TOKEN')

    begin
      orig_timestamp = get_latest_production_repo_query_timestamp
    rescue QueryError, SystemCallError => e
      abort("ERROR: failed to query latest web server timestamp: #{e.message}")
    end

    log_notice 'Restarting web servers'
    initiate_restart_web_server

    log_notice 'Waiting until web server is restarted'
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT_SECS
    while true
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        abort('ERROR: Timed out waiting for web server to restart')
      end

      begin
        timestamp = get_latest_production_repo_query_timestamp
      rescue QueryError, SystemCallError => e
        log_info "Error querying latest web server timestamp: #{e.message}"
        log_info 'Retrying in 4s...'
        sleep 4
        next
      end

      if timestamp == orig_timestamp
        log_info 'Web server has not restarted yet; waiting...'
        sleep 4
        next
      end

      log_info 'Web server has restarted'
      break
    end
  end

  def initiate_restart_web_server
    log_info "POSTing to #{RESTART_WEB_SERVER_API_URL}"
    uri = URI(RESTART_WEB_SERVER_API_URL)
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{ENV['ID_TOKEN']}"

    resp = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if resp.code.to_i / 100 != 2
      abort("ERROR: failed to restart web server: #{resp.code} #{resp.message}: #{resp.body}")
    end
  end

  def get_latest_production_repo_query_timestamp
    uri = URI(LATEST_REPO_QUERY_TIMESTAMP_URL)
    resp = Net::HTTP.get_response(uri)
    if resp.code.to_i / 100 == 2
      resp.body
    else
      raise QueryError, "#{resp.code} #{resp.message}: #{resp.body}"
    end
  end
end

RestartWebServer.new.main
