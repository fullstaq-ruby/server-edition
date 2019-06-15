# A data structure for tracking the progress of various tasks
# that may run in parallel.
#
# We want to achieve the following output format:
# ----------------------
# Sources:                                                          <-- this is a Category
#  * Ruby 2.6.3                  : Not started|In progress|Done [3s]  <-- this is a single-stage Entry (containing 1 Stage)
#  * Jemalloc                    : Not started|In progress|Done [6s]
#
# Rbenv:
#  * DEB                         : Done           [12s]
#  * RPM                         : Done           [10s]
#
# Jemalloc
#  * centos-7                    : Not started
#  * ubuntu-18.04                : In progress    [6m 1s]
#
# Ruby 2.6
#  * RPM centos-7 jemalloc                                            <-- this is a multi-stage Entry
#      Build                     : Done           [6m 21s]            <-- this is a Stage
#      Package                   : In progress    [6m 21s]
#      Test                      : Not started
#  * DEB ubuntu-18.04 malloctrim
#      Build                     : Not started
#      Package                   : Not started
#      Test                      : Not started
# ----------------------

require 'thread'
require 'paint'

class ProgressTracker
  COLORS = [
    "CadetBlue1",
    "yellow1",
    "burlywood1",
    "DarkOliveGreen1",
    "gold",
    "LightSalmon",
    "DarkTurquoise",
    "chocolate1",
    "SpringGreen1",
    "HotPink1",
    "GreenYellow",
    "MediumOrchid1",
    "DeepSkyBlue",
    "chartreuse1",
    "aquamarine"
  ].freeze

  class Category < Struct.new(:tracker, :name, :entries)
    def define_entry(entry_name, single_stage_id)
      entry = (entries[entry_name] ||= create_entry(entry_name, single_stage_id))
      yield entry if block_given?
      entry
    end

  private
    def create_entry(entry_name, single_stage_id)
      entry = Entry.new(tracker, entry_name, {})
      if single_stage_id
        entry.define_stage(entry_name, single_stage_id)
      end
      entry
    end
  end

  class Entry < Struct.new(:tracker, :name, :stages)
    def define_stage(stage_name, stage_id)
      stage = (stages[stage_name] ||= Stage.new(tracker, stage_name, stage_id,
        tracker.next_color, :not_started, nil, nil))
      yield stage if block_given?
      stage
    end

    def multi_stage?
      stages.size > 1
    end

    def status
      if multi_stage?
        raise 'This is a multistage entry'
      else
        stages.first[1].status
      end
    end

    def display_status
      if multi_stage?
        raise 'This is a multistage entry'
      else
        stages.first[1].display_status
      end
    end

    def duration_description
      if multi_stage?
        raise 'This is a multistage entry'
      else
        stages.first[1].duration_description
      end
    end

    def track_work(&block)
      if multi_stage?
        raise 'This is a multistage entry'
      else
        stages.first[1].track_work(&block)
      end
    end
  end

  class Stage < Struct.new(:tracker, :name, :id, :color, :status, :start_time, :end_time)
    attr_reader :log_file

    def track_work
      tracker.mutex.synchronize do
        self.status = :in_progress
        self.start_time = Time.now
      end
      begin
        Thread.current[:progress_tracking_stage] = self
        @log_file = File.open("#{Support.logs_dir}/#{id.gsub(':', '-')}.log", 'w:utf-8')
        yield
      rescue Exception => e
        tracker.mutex.synchronize do
          self.status = :error
          self.end_time = Time.now
        end
        raise e
      else
        tracker.mutex.synchronize do
          self.status = :done
          self.end_time = Time.now
        end
      ensure
        if @log_file
          @log_file.close
          @log_file = nil
        end
        Thread.current[:progress_tracking_stage] = nil
      end
    end

    def done?
      status == :done
    end

    def error?
      status == :error
    end

    def display_status
      case status
      when :not_started
        'Not started'
      when :in_progress
        'In progress'
      when :done
        'Done'
      when :error
        'Error'
      end
    end

    def duration_description
      if status == :not_started
        nil
      else
        Support.distance_of_time_in_hours_and_minutes(start_time,
          end_time || Time.now)
      end
    end
  end

  attr_reader :mutex

  def initialize
    @categories = {}
    @start_time = Time.now
    @mutex = Mutex.new
    @next_color_index = 0
  end

  def next_color
    result = COLORS[@next_color_index]
    @next_color_index = (@next_color_index + 1) % COLORS.size
    result
  end

  def define_category(name)
    category = (@categories[name] ||= Category.new(self, name, {}))
    yield category if block_given?
    category
  end

  def finished?
    @categories.values.all? do |category|
      category.entries.values.all? do |entry|
        entry.stages.values.all? do |stage|
          stage.done?
        end
      end
    end
  end

  def has_errors?
    @categories.values.any? do |category|
      category.entries.values.any? do |entry|
        entry.stages.values.any? do |stage|
          stage.error?
        end
      end
    end
  end

  def write(io, colorize = true)
    if colorize
      colors = {
        success: [:green],
        error: [:red],
        neutral: []
      }
    else
      colors = {
        success: [],
        error: [],
        neutral: []
      }
    end

    @mutex.synchronize do
      io.puts "Current time: #{Support.format_time(Time.now)}"
      io.puts "Start time  : #{Support.format_time(@start_time)}"
      io.puts "Duration    : #{duration_description}"
      if finished?
        io.puts Paint["*** FINISHED ***", *colors[:success]]
      end
      if has_errors?
        io.puts Paint["*** THERE WERE ERRORS ***", *colors[:error]]
      end

      io.puts
      @categories.each_value do |category|
        io.puts "#{category.name}:"
        category.entries.each_value do |entry|
          if entry.multi_stage?
            io.printf " * %s\n", entry.name
            entry.stages.each_value do |stage|
              io.printf "     %-25s: %s    %s\n",
                stage.name,
                pick_status_color(stage, "%-14s", colors),
                stage.duration_description
            end
          else
            io.printf " * %-27s : %s    %s\n",
              entry.name,
              pick_status_color(entry, "%-14s", colors),
              entry.duration_description
          end
        end
        io.puts
      end
    end
  end

  def duration_description
    Support.distance_of_time_in_hours_and_minutes(@start_time, Time.now)
  end

private
  def pick_status_color(entry_or_stage, format, colors)
    case entry_or_stage.status
    when :done
      colors = colors[:success]
    when :error
      colors = colors[:error]
    else
      colors = colors[:neutral]
    end

    Paint[sprintf(format, entry_or_stage.display_status), *colors]
  end
end
