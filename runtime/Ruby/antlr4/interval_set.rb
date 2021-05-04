# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.

require_relative "token"

# stop is not included!
class Interval
  attr_accessor(:start, :stop)

  def initialize(start, stop)
    @start = start
    @stop = stop
  end

  def clone
    Interval.new(@start, @stop)
  end

  def contains?(item)
    item >= @start and item < @stop
  end

  def to_s
    return @start.to_s if @start == (@stop - 1)
    "#{@start}..#{@stop - 1}"
  end

  def size
    @stop - @start
  end
end

class IntervalSet
  attr_accessor(:intervals, :read_only)

  def initialize
    @intervals = nil
    @read_only = false
  end

  def first(v)
    return Token::INVALID_TYPE if @intervals.nil? or @intervals.size == 0
    @intervals[0].start
  end

  def add_one(v)
    add_interval(Interval.new(v, v + 1))
  end

  def add_range(l, h)
    add_interval(Interval.new(l, h + 1))
  end

  def add_interval(to_add)
    if @intervals.nil?
      @intervals = []
      @intervals << to_add.clone()
    else
      # find insert pos
      (0..(@intervals.size - 1)).each { |pos|
        existing = @intervals[pos]
        # distinct range -> insert
        if to_add.stop < existing.start
          @intervals.insert(pos, to_add)
          return
          # contiguous range -> adjust
        elsif to_add.stop == existing.start
          @intervals[pos].start = to_add.start
          return
          #  overlapping range -> adjust and reduce
        elsif to_add.start <= existing.stop
          @intervals[pos] = Interval.new([existing.start, to_add.start].min,
                                         [existing.stop, to_add.stop].max)
          reduce(pos)
          return
        end
      }
      # greater than any existing
      @intervals << to_add.clone()
    end
  end

  def add_set(other)
    unless @intervals.nil?
      other.intervals.each { |to_add| add_interval(to_add) }
    end
  end

  def reduce(pos)
    # only need to reduce if pos is not the last
    if pos < (@intervals.size - 1)
      current = @intervals[pos]
      nnext = @intervals[pos + 1]
      # if next contained in current
      if current.stop >= nnext.stop
        @intervals.delete_at(pos + 1)
        reduce(pos)
      elsif current.stop >= nnext.stop
        @intervals = Interval.new(current.start, nnext.stop)
        @intervals.delete_at(pos + 1)
      end
    end
  end

  def complement(start, stop)
    result = IntervalSet.new
    result.add_interval(Interval.new(start, stop + 1))
    @intervals.each { |to_remove| result.remove_range(to_remove) } unless @intervals.nil?
    result
  end

  def contains?(item)
    return false if @intervals.nil?
    (0..(@intervals.size - 1)).each { |k|
      return true if @intervals[k].contains?(item)
    }
    return false
  end

  def remove_range(to_remove)
    if to_remove.start == (to_remove.stop - 1)
      remove_one(to_remove.start)
    elsif not @intervals.nil?
      pos = 0
      (0..(@intervals.size - 1)).each { |n|
        existing = @intervals[pos]
        # intervals are ordered
        return if to_remove.stop <= existing.start
        # check for including range, split it
        if to_remove.start > existing.start and to_remove.stop < existing.stop
          @intervals[pos] = Interval.new(existing.start, to_remove.start)
          x = Interval.new(to_remove.stop, existing.stop)
          @intervals.insert(pos, x)
          return
        end
        #  check for included range, remove it
        if to_remove.start <= existing.start and to_remove.stop >= existing.stop
          @intervals.delete_at(pos)
          pos -= 1 # need another pass
          # check for lower boundary
        elsif to_remove.start < existing.stop
          @intervals[pos] = Interval.new(existing.start, to_remove.start)
          # check for upper boundary
        elsif to_remove.stop < existing.stop
          @intervals[pos] = Interval.new(to_remove.stop, existing.stop)
        end
        pos += 1
      }
    end
  end

  def remove_one(value)
    unless @intervals.nil?
      (0..(@intervals.size - 1)).each { |i|
        existing = @intervals[i]
        # intervals are ordered
        return if value < existing.start
        # check for single value range
        if value == existing.start and value == (existing.stop - 1)
          @intervals.delete_at(i)
          return
        end
        # check for lower boundary
        if value == existing.start
          @intervals[i] = Interval.new(existing.start + 1, existing.stop)
          return
        end
        # check for upper boundary
        if value == (existing.stop - 1)
          @intervals[i] = Interval.new(existing.start, existing.stop - 1)
          return
        end
        # split existing range
        if value < (existing.stop - 1)
          replace = Interval.new(existing.start, value)
          existing.start = value + 1
          @intervals.insert(i, replace)
        end
      }
    end
  end

  def to_s(literal_names = nil, symbolic_names = nil, elems_are_char = false)
    return "{}" if @intervals.nil?
    return to_token_strng(literal_names, symbolic_names) if (not literal_names.nil?) or (not symbolic_names.nil?)
    return to_char_string() if elems_are_char
    to_index_string()
  end

  def to_char_string
    names = []
    (0..(@intervals.size - 1)).each { |i|
      existing = @intervals[i]
      if existing.stop == (existing.start + 1)
        if existing.start == Token::EOF
          names << "<EOF>"
        else
          names << "'#{existing.start.chr(Encoding::UTF_8)}'"
        end
      else
        names << "'#{existing.start.chr(Encoding::UTF_8)}'..'#{(existing.stop - 1).chr(Encoding::UTF_8)}'"
      end
    }
    return "{#{names.join(", ")}}" if names.size > 1
    names[0]
  end

  def to_index_string
    names = []
    (0..(@intervals.size - 1)).each { |i|
      existing = @intervals[i]
      if existing.stop == (existing.start +1)
        if existing.start == Token::EOF
          names << "<EOF>"
        else
          names << existing.start.to_s
        end
      else
        names << "#{existing.start}..#{existing.stop - 1}"
      end
    }
    return "{#{names.join(", ")}}" if names.size > 1
    names[0]
  end

  def to_token_string(literal_names, symbolic_names)
    names = []
    (0..(@intervals.size - 1)).each { |i|
      existing = @intervals[i]
      (existing.start..(existing.stop - 1)).each { |j|
        names << element_name(literal_names, symbolic_names, j)
      }
    }
    return "{#{names.join(", ")}}" if names.size > 1
    names[0]
  end

  def element_name(literal_names, symbolic_names, token)
    return "<EOF>" if token == Token::EOF
    return "<EPSILON>" if token == Token::EPSILON
    literal_names[token] || symbolic_names[token]
  end

  def size
    @intervals.map(&:size).reduce(:+)
  end
end
