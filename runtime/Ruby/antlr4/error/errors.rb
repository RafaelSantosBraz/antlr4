# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "../interval_set"
require_relative "../atn/transition"

# The root of the ANTLR exception hierarchy. In general, ANTLR tracks just
#  3 kinds of errors: prediction errors, failed predicate errors, and
#  mismatched input errors. In each case, the parser knows where it is
#  in the input, where it is in the ATN, the rule invocation stack,
#  and what kind of problem occurred.

class RecognitionException < Exception
  attr_accessor(:message, :recognizer, :input, :ctx, :offending_token,
                :offending_state)

  def initialize(message = nil, recognizer = nil, input = nil, ctx = nil)
    super(message)
    @message = message
    @recognizer = recognizer
    @input = input
    @ctx = ctx
    # The current {@link Token} when an error occurred. Since not all streams
    # support accessing symbols by index, we have to track the {@link Token}
    # instance itself.
    @offending_token = nil
    # Get the ATN state number the parser was in at the time the error
    # occurred. For {@link NoViableAltException} and
    # {@link LexerNoViableAltException} exceptions, this is the
    # {@link DecisionState} number. For others, it is the state whose outgoing
    # edge we couldn't match.
    @offending_state = -1
    @offending_state = recognizer.state unless recognizer.nil?
  end

  # <p>If the state number is not known, this method returns -1.</p>

  #
  # Gets the set of input symbols which could potentially follow the
  # previously matched symbol at the time this exception was thrown.
  #
  # <p>If the set of expected tokens is not known and could not be computed,
  # this method returns {@code null}.</p>
  #
  # @return The set of token types that could potentially follow the current
  # state in the ATN, or {@code null} if the information is not available.
  #/
  def get_expected_tokens
    if not @recognizer.nil?
      return @recognizer.atn.get_expected_tokens(@offending_state, @ctx)
    end
    nil
  end

  # <p>If the state number is not known, this method returns -1.</p>
  def to_s
    @message
  end
end

class LexerNoViableAltException < RecognitionException
  attr_accessor(:start_index, :dead_end_configs)

  def initialize(lexer, input, start_index, dead_end_configs)
    super("", lexer, input, nil)
    @start_index = start_index
    @dead_end_configs = dead_end_configs
  end

  def to_s
    symbol = ""
    if @start_index >= 0 and @start_index < @input.size
      symbol = @input.get_text(Interval.new(@start_index, @start_index))
    end
    "LexerNoViableAltException('#{symbol}')"
  end
end

# Indicates that the parser could not decide which of two or more paths
#  to take based upon the remaining input. It tracks the starting token
#  of the offending input and also knows where the parser was
#  in the various paths when the error. Reported by reportNoViableAlternative()
#
class NoViableAltException < RecognitionException
  attr_accessor(:dead_end_configs)

  def initialize(recognizer, input = nil, start_token = nil,
                             offending_token = nil, dead_end_configs = nil,
                             ctx = nil)
    ctx = recognizer.ctx if ctx.nil?
    offending_token = recognizer.get_current_token() if offending_token.nil?
    start_token = recognizer.get_current_token() if start_token.nil?
    input = recognizer.get_input_stream() if input.nil?
    super("", recognizer, input, ctx)
    # Which configurations did we try at input.index() that couldn't match input.LT(1)?#
    @dead_end_configs = dead_end_configs
    # The token object at the start index; the input stream might
    # 	not be buffering tokens so get a reference to it. (At the
    #  time the error occurred, of course the stream needs to keep a
    #  buffer all of the tokens but later we might not have access to those.)
    @start_token = start_token
    @offending_token = offending_token
  end
end

# This signifies any kind of mismatched input exceptions such as
#  when the current input does not match the expected token.
#
class InputMismatchException < RecognitionException
  def initialize(recognizer)
    super("", recognizer, recognizer.get_input_stream(), recognizer.ctx)
    @offending_token = recognizer.get_current_token()
  end
end

# A semantic predicate failed during validation.  Validation of predicates
#  occurs when normally parsing the alternative just like matching a token.
#  Disambiguating predicate evaluation occurs when we test a predicate during
#  prediction.
class FailedPredicateException < RecognitionException
  attr_accessor(:rule_index, :predicate_index, :predicate)

  def initialize(recognizer, predicate = nil, message = nil)
    super(format_message(predicate, message), recognizer,
          recognizer.get_input_stream(), recognizer.ctx)
    s = recognizer.interp.atn.states[recognizer.state]
    trans = s.transitions[0]
    if trans.is_a? PredicateTransition
      @rule_index = trans.rule_index
      @predicate_index = trans.pred_index
    else
      @rule_index = 0
      @predicate_index = 0
    end
    @predicate = predicate
    @offending_token = recognizer.get_current_token()
  end

  def format_message(predicate, message)
    if not message.nil?
      return message
    end
    "failed predicate: {#{predicate}}?"
  end
end

class ParseCancellationException < Exception
end
