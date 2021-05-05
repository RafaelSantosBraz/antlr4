#
# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "input_stream"
require_relative "utils"

#
#  This is an InputStream that is loaded from a file all at once
#  when you construct the object.
#

class FileStream < InputStream
  attr_accessor(:file_name)

  def initialize(file_name, decode_to_unicode_codepoints)
    data = File.read(file_name, :encoding => FILE_ENCODING)
    super(data, decode_to_unicode_codepoints)
    @file_name = file_name
  end
end
