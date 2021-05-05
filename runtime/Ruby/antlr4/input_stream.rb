#
# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "token"
require_relative "utils"

#*
# If decode_to_unicode_codepoints is true, the input is treated
# as a series of Unicode code points.
#
# Otherwise, the input is treated as a series of 16-bit UTF-16 code
# units.
#/
class InputStream
  attr_accessor(:name, :strdata, :decode_to_unicode_codepoints, :data)

  def initialize(data, decode_to_unicode_codepoints = false)
    @name = "<empty>"
    @strdata = data
    @decode_to_unicode_codepoints = decode_to_unicode_codepoints
    @_index = 0
    @data = []
    if @decode_to_unicode_codepoints
      @data = @strdata.codepoints()
    else
      @data = @strdata.chars.map(&:ord)
    end
    @_size = @data.size
  end

  # Reset the stream so that it's in the same state it was
  # when the object was created#except* the data array is not
  # touched.
  #
  def reset
    @_index = 0
  end

  def consume
    if @_index >= @_size
      # raise(Exception, "Token::EOF AssertionError") unless lA(1) == Token::EOF
      raise Exception, "cannot consume EOF"
    end
    @_index += 1
  end

  def la(offset)
    return 0 if offset == 0 # undefined
    offset += 1 if offset < 0 # e.g., translate LA(-1) to use offset=0
    pos = @_index + offset - 1
    return Token::EOF if pos < 0 or pos >= @_size # invalid
    @data[pos]
  end

  def lt(offset)
    la(offset)
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
    if index <= @_index
      @_index = index  # just jump; don't update stream state (line, ...)
      return
    end
    # seek forward
    @_index = [index, @_size].min
  end

  def get_text(start, stop)
    stop = (@_size - 1) if stop >= @_size
    if start >= @_size
      return ""
    else
      if @decode_to_unicode_codepoints
        return (start..stop).map { |i| @data[i].chr(DECODE_ENCODING) }.join
      else
        return @strdata[start..stop]
      end
    end
  end

  def to_s
    @strdata
  end

  def index
    @_index
  end

  def size
    @_size
  end
end
