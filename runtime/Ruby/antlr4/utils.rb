# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require "set"

# encoding used to convert from int to str
DECODE_ENCODING = Encoding::UTF_8

# encoding used for reading files
FILE_ENCODING = Encoding::UTF_8

class CustomSetForATNConfigSet < Set
  def add(value)
    value.is_inside_set = true
    if self.include? value
      return self.find { |v| v.eql? value }
    end
    super(value)
    value
  end
end
