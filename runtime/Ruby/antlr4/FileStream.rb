#
# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

#
#  This is an InputStream that is loaded from a file all at once
#  when you construct the object.
#

require_relative "InputStream"

class FileStream < InputStream
  attr_accessor(:fileName)

  def initialize(fileName)
    super(readDataFrom(fileName))
    @fileName = fileName
  end

  def readDataFrom(fileName)
    File.read(fileName)
  end
end
