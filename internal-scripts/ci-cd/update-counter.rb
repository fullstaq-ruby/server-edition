#!/usr/bin/env ruby
require 'distributed-lock-google-cloud-storage'
require 'logger'
require_relative '../../lib/shell_scripting_support'

# Atomatically updates a counter located in a Google Cloud Storage object.
# Two operations are supported: setting an exact value, or incrementing the value by 1.
#
# Outputs the new value to a Github Actions output parameter named 'value'.
class IncrementCounterApp
  include ShellScriptingSupport

  def main
    require_envvar('BUCKET_NAME')
    require_envvar('LOCK_PATH')
    require_envvar_enum('OPERATION', ['set', 'increment'])
    require_envvar('COUNTER_PATH')
    optional_envvar('GCLOUD_KEY')
    if ENV['OPERATION'] == 'set'
      require_envvar('COUNTER_VALUE')
    end

    logger = create_logger
    client = get_storage_client
    bucket = get_storage_bucket(client)

    lock = create_lock(logger)
    new_value = lock.synchronize do
      case ENV['OPERATION']
      when 'set'
        new_value = set_value
      when 'increment'
        new_value = increment_value(bucket)
      end

      bucket.create_file(
        StringIO.new(new_value.to_s),
        ENV['COUNTER_PATH'],
        cache_control: 'no-store')
      new_value
    end

    logger.info "Counter '#{ENV['COUNTER_PATH']}' updated: value=#{new_value}"
    puts "::set-output name=value::#{new_value}"
  end

private
  def set_value
    ENV['COUNTER_VALUE'].to_i
  end

  def increment_value(bucket)
    file = bucket.file(ENV['COUNTER_PATH'])
    if file.nil?
      1
    else
      file.download.string.to_i + 1
    end
  end

  def create_logger
    logger = Logger.new($stderr)
    logger.level = Logger::DEBUG
    logger
  end

  def create_lock(logger)
    if ENV['GCLOUD_KEY']
      options = {
        cloud_storage_options: {
          credentials: ENV['GCLOUD_KEY']
        }
      }
    else
      options = {}
    end
    DistributedLock::GoogleCloudStorage::Lock.new(
      bucket_name: ENV['BUCKET_NAME'],
      path: ENV['LOCK_PATH'],
      logger: logger,
      **options)
  end

  def get_storage_client
    if ENV['GCLOUD_KEY']
      Google::Cloud::Storage.new(credentials: ENV['GCLOUD_KEY'])
    else
      Google::Cloud::Storage.new
    end
  end

  def get_storage_bucket(client)
    client.bucket(ENV['BUCKET_NAME'], skip_lookup: true)
  end
end

IncrementCounterApp.new.main
