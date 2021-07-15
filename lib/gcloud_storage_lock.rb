# frozen_string_literal: true

require 'time'
require 'logger'

# A distributed lock that works using a Google Cloud Storage object.
#
# @example Idiomatic usage
#   lock = GCloudStorageLock.new(
#     url: 'gs://bucket-name/object-path',
#     stale_time: 120,
#     refresh_time: 15,
#   )
#   lock.synchronize do
#     do_some_work
#
#     # IMPORTANT: when performing a long-running operation,
#     # _periodically_ check whether the lock is still healthy.
#     # This call throws an exception if it's not healthy.
#     #
#     # Learn more in section "Lock health check".
#     lock.check_health!
#
#     do_more_work
#   end
#
# ## Dependencies
#
# We shell out to `gsutil` under the hood.
#
# ## Algorithm
#
# The algorithm is compatible with https://github.com/mco-gh/gcslock.
# If and only if the object exists, then we consider the lock to be held.
# We also introduce an compatible improvement over the gslock algorithm:
# we detect stale locks.
#
# ## Stale locks
#
# A lock can become stale when the process that held it, crashes and
# doesn't clean up the lock object. So when using GCloudStorageLock, one
# must specify how old a lock object may be before we consider it stale.
# Upon acquiring a lock, GCloudStorageLock cleans up the lock if it detects
# it as stale.
#
# ## Long-running operations & refreshing locks
#
# It's safe to use GCloudStorageLock for long-running operations that can
# last longer than the stale time. This works by using a background
# thread which periodically refreshes the lock's timestamp while the
# lock is held.
#
# ## Lock health check
#
# Refreshing the lock may fail, e.g. because of a network problem with
# Google Cloud Storage. This is dangerous when performing long-running
# operations: the lock can become stale while we're still performing the
# operation.
#
# To prevent this from happening, one should check the lock's health
# periodically during a long-running operation, by calling `#healthy?`
# or `#check_health!`. One should abort the operation upon detecting
# an unhealthy state.
#
# "Unhealthy" means that a lock refresh operation failed
# `MAX_REFRESH_FAILS` times in succession.
class GCloudStorageLock
  class Error < StandardError; end
  class CommandError < Error; end
  class LockError < Error; end
  class MetadataParseError < Error; end
  class NotLockedError < Error; end
  class LockUnhealthyError < Error; end
  class TimeoutError < Error; end

  DEFAULT_STALE_TIME = 5 * 60

  # Maximum number of times that the lock refresh operation may fail in
  # succession, before declaring that the lock is unhealthy.
  MAX_REFRESH_FAILS = 3

  # @param url [String] A Google Cloud Storage object URL that will be used
  #   for locking. For example `gs://bucket-name/object-path`
  #
  # @param stale_time [Integer, Float] The lock is considered stale if its
  #   age (in seconds) is older than this value. This value should be generous:
  #   on the order of minutes.
  #
  #   Default: `DEFAULT_STALE_TIME`
  #
  # @param refresh_interval [Integer, Float, nil] We'll refresh the lock's
  #   timestamp every `refresh_interval` seconds. This value should be many
  #   times smaller than `stale_time`, so that we can detect an unhealthy
  #   lock long before it becomes stale.
  #
  #   This value must be smaller than `stale_time / MAX_REFRESH_FAILS`.
  #
  #   Default: `stale_time / 8`
  #
  # @param logger [Logger]
  #
  # @note The logger must either be thread-safe, or it musn't be used by anything
  #   besides this GCloudStorageLock instance. This is because the logger will be
  #   written to by a background thread.
  def initialize(url:, stale_time: DEFAULT_STALE_TIME, refresh_interval: nil, logger: Logger.new($stderr))
    if refresh_interval && refresh_interval >= stale_time.to_f / MAX_REFRESH_FAILS
      raise ArgumentError, 'refresh_interval must be smaller than stale_time / MAX_REFRESH_FAILS'
    end

    @url = url
    @stale_time = stale_time
    @refresh_interval = refresh_interval || stale_time / 8.0
    @logger = logger

    @refresher_mutex = Mutex.new
    @refresher_cond = ConditionVariable.new
  end

  def locked?
    !@refresher_thread.nil?
  end

  def lock(timeout: @stale_time)
    sleep_time = 1
    deadline = monotonic_time + timeout

    while true
      break if upsert_lock_object(if_generation_match: 0)

      raise TimeoutError if monotonic_time >= deadline

      exists, generation, update_time = get_lock_object_metadata
      if exists && lock_stale?(update_time)
        @logger.warn 'Lock is stale. Resetting lock'
        delete_lock_object(if_generation_match: generation)
      end

      @logger.info("Unable to acquire lock. Will try again in #{sleep_time.to_i} seconds")
      sleep(sleep_time + rand)
      sleep_time = bump_sleep_time(sleep_time)
    end

    exists, @generation, _ = get_lock_object_metadata
    raise LockError, 'Lock object does not exist after creating it' if !exists

    spawn_refresher_thread
    nil
  end

  def unlock
    raise NotLockedError, 'Not locked' if !locked?
    shutdown_refresher_thread
    # Matching the generation is important. If the lock is stale
    # then we don't want to race with another process that may
    # have recreated the lock.
    delete_lock_object(if_generation_match: @generation)
  end

  def synchronize(...)
    lock(...)
    begin
      yield
    ensure
      unlock
    end
  end

  def healthy?
    raise NotLockedError, 'Not locked' if !locked?
    @refresher_thread.alive?
  end

  def check_health!
    raise LockUnhealthyError, 'Lock is not healthy' if !healthy?
  end

private
  def run_command_capture_stderr(command)
    IO.pipe('UTF-8') do |a, b|
      pid = Process.spawn(
        *command,
        in: ['/dev/null', 'r'],
        out: ['/dev/null', 'a'],
        err: b,
        close_others: true
      )
      begin
        b.close
        output = a.read
      rescue => e
        begin
          Process.kill('TERM', pid)
        rescue Errno::ESRCH, Errno::EPERM
        end
        raise e
      end
      Process.waitpid(pid)
      [output, $?]
    end
  end

  def upsert_lock_object(if_generation_match:)
    command = [
      'gsutil',
      '-q',
      '-h',
      "x-goog-if-generation-match:#{if_generation_match}",
      'cp',
      '-',
      @url,
    ]
    @logger.debug "Running command: #{command.join(' ')}"
    output, status = run_command_capture_stderr(command)
    if status.success?
      true
    elsif output =~ /412 Precondition Failed/
      false
    else
      raise CommandError, output
    end
  end

  def update_lock_object
    command = [
      'ggsutil',
      '-q',
      'cp',
      '-',
      @url,
    ]
    @logger.debug "Running command: #{command.join(' ')}"
    output, status = run_command_capture_stderr(command)
    raise CommandError, output if !status.success?
  end

  def delete_lock_object(if_generation_match:)
    command = [
      'gsutil',
      '-q',
      '-h',
      "x-goog-if-generation-match:#{if_generation_match}",
      'rm',
      @url,
    ]
    @logger.debug "Running command: #{command.join(' ')}"
    output, status = run_command_capture_stderr(command)
    if status.success? || output =~ /No URLs matched/
      true
    elsif output =~ /412 Precondition Failed/
      false
    else
      raise CommandError, output
    end
  end

  def get_lock_object_metadata
    command = ['gsutil', 'stat', @url]
    options = {
      in: ['/dev/null', 'r'],
      err: [:child, :out],
      close_others: true,
    }
    output = IO.popen(command, 'r:utf-8', options) do |io|
      io.read
    end

    if !$?.success?
      if output =~ /No URLs matched/
        return [false]
      else
        raise CommandError, output
      end
    end

    if output !~ /Generation: (.+)/
      raise MetadataParseError, 'Unable to extract generation from metadata'
    end
    generation = $1.strip.to_s

    if output !~ /Update time: (.+)/
      raise MetadataParseError, 'Unable to extract update time from metadata'
    end
    update_time = Time.parse($1.strip)

    [true, generation, update_time]
  end

  def lock_stale?(update_time)
    update_time < Time.now - @stale_time
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def bump_sleep_time(sleep_time)
    [30, sleep_time * 2].min
  end

  def spawn_refresher_thread
    @refresher_thread = Thread.new do
      refresher_thread_main
    end
  end

  def shutdown_refresher_thread
    @refresher_mutex.synchronize do
      @refresher_quit = true
      @refresher_cond.signal
    end
    @refresher_thread.join
    @refresher_thread = nil
  end

  def refresher_thread_main
    fail_count = 0
    next_refresh_time = monotonic_time + @refresh_interval

    @refresher_mutex.synchronize do
      while !@refresher_quit && fail_count <= MAX_REFRESH_FAILS
        timeout = [0, next_refresh_time - monotonic_time].max
        @logger.debug "Next lock refresh in #{timeout}s"
        @refresher_cond.wait(@refresher_mutex, timeout)
        break if @refresher_quit

        # Timed out; refresh now
        next_refresh_time = monotonic_time + @refresh_interval
        @refresher_mutex.unlock
        begin
          refreshed = refresh_lock
        ensure
          @refresher_mutex.lock
        end

        if refreshed
          fail_count = 0
        else
          fail_count += 1
        end
      end

      if fail_count > MAX_REFRESH_FAILS
        @logger.error("Lock refresh failed #{fail_count} times in succession." \
          ' Declaring lock as unhealthy')
      end
    end
  end

  def refresh_lock
    @logger.info 'Refreshing lock'
    begin
      if !upsert_lock_object(if_generation_match: @generation)
        raise 'Lock object has an unexpected generation number'
      end

      exists, @generation, _ = get_lock_object_metadata
      if !exists
        raise 'Lock object does not exist'
      end

      @logger.debug 'Done refreshing lock'
      true
    rescue => e
      @logger.error("Error refreshing lock: #{e}")
      false
    end
  end
end
