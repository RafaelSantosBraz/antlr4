#
# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

#
#  Vacuum all input from a string and then treat it like a buffer.
#

require_relative "Token"

class InputStream
  attr_accessor(:name, :strdata, :index, :data, :size)

  def initialize(data)
    @name = "<empty>"
    @strdata = data
    loadString()
  end

  def loadString
    @index = 0
    @data = @strdata.chars.map(&:ord)
    @size = @data.size
  end

  # Reset the stream so that it's in the same state it was
  #  when the object was created *except* the data array is not
  #  touched.
  #
  def reset
    @index = 0
  end

  def consume
    if @index >= @size
      raise(Exception, "Token::EOF AssertionError") unless lA(1) == Token::EOF
      raise Exception, "cannot consume EOF"
    end
    @index += 1
  end

  def lA(offset)
    return 0 if offset == 0 # undefined
    offset += 1 if offset < 0 # e.g., translate LA(-1) to use offset=0
    pos = @index + offset - 1
    return Token::EOF if pos < 0 or pos >= @size # invalid
    @data[pos]
  end

  def lT(offset)
    lA(offset)
  end

  # mark/release do nothing; we have entire buffer
  def mark
    -1
  end

  def release(marker)
  end

  # consume() ahead until p==_index; can't just set p=_index as we must
  # update line and column. If we seek backwards, just set p
  #
  def seek(index)
    if index <= @index
      @index = index  # just jump; don't update stream state (line, ...)
      return
    end
    # seek forward
    @index = [index, @size].min
  end

  def getText(start, stop)
    stop = (@size - 1) if stop >= @size
    if start >= @size
      return ""
    else
      return @strdata[start..stop]
    end
  end

  def to_s
    @strdata
  end
end
