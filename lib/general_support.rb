# frozen_string_literal: true

module GeneralSupport
  ROOT = File.absolute_path(File.dirname(__FILE__) + '/..')

  # Make instance methods available as class methods
  extend self


  def unindent(amount, &block)
    indentation = /^#{' ' * amount}/
    lines = capture(&block).split("\n")
    lines.map! { |l| l.sub(indentation, '') }
    @erb_out << lines.join("\n")
  end

  def slug(str)
    str.to_s.scan(/[a-z0-9]+/).join('_')
  end

  def capture
    pos = @erb_out.size
    yield
    @erb_out.slice!(pos..@erb_out.size)
  end

  # A single-value file is a file such as environments/ubuntu-18.04/image_tag.
  # It contains exactly 1 line of usable value, and may optionally contain
  # comments that start with '#', which are ignored.
  def read_single_value_file(path)
    contents = File.read(path, mode: 'r:utf-8')
    contents.split("\n").grep_v(/^#/).first.strip
  end

  # Puts an array's elements into at most N buckets. For example:
  #
  #   bucketize([:a, :b, :c, :d, :e], 3)
  #
  # Outputs:
  #
  #   [
  #     [:a, :d],
  #     [:b, :e],
  #     [:c],
  #   ]
  def bucketize(ary, n)
    result = []
    ary.each_with_index do |elem, i|
      bucket = (result[i % n] ||= [])
      bucket << elem
    end
    result
  end
end
