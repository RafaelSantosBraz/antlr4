# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require "set"

# encoding used to convert from int to str
DECODE_ENCODING = Encoding::UTF_8

# encoding used for reading files
FILE_ENCODING = Encoding::UTF_8

# custom Set to handle @is_inside_set of ATNConfig
class CustomSetForATNConfigSet < Set
  def add(value)
    value.is_inside_set = true
    super(value)
    value.is_inside_set = false
    self
  end

  def include?(value)
    value.is_inside_set = true
    resp = super(value)
    value.is_inside_set = false
    resp
  end
end
