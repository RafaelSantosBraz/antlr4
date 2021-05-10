# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

class ATNDeserializationOptions
  attr_accessor(:read_only, :verify_atn, :generate_rule_bypass_transitions)

  def initialize(copy_from = nil)
    @read_only = false
    @verify_atn = copy_from.nil? ? true : copy_from.verify_atn
    @generate_rule_bypass_transitions = copy_from.nil? ? false : copy_from.generate_rule_bypass_transitions
  end
end

ATNDeserializationOptions::DEFAULT_OPTIONS = ATNDeserializationOptions.new
(ATNDeserializationOptions::DEFAULT_OPTIONS).read_only = true
