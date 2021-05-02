# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "../InputStream"
require_relative "../ParserRuleContext"
require_relative "../Recognizer"
require_relative "../atn/Transition"

class UnsupportedOperationException < Exception
end

class IllegalStateException < Exception
end

class CancellationException < IllegalStateException
end

# The root of the ANTLR exception hierarchy. In general, ANTLR tracks just
#  3 kinds of errors: prediction errors, failed predicate errors, and
#  mismatched input errors. In each case, the parser knows where it is
#  in the input, where it is in the ATN, the rule invocation stack,
#  and what kind of problem occurred.

class RecognitionException < Exception
  attr_accessor(:message, :recognizer, :input, :ctx, :offendingToken, :offendingState)

  def initialize(message = nil, recognizer = nil, input = nil, ctx = nil)
    super(message)
    @message = message
    @recognizer = recognizer
    @input = input
    @ctx = ctx
    # The current {@link Token} when an error occurred. Since not all streams
    # support accessing symbols by index, we have to track the {@link Token}
    # instance itself.
    @offendingToken = nil
    # Get the ATN state number the parser was in at the time the error
    # occurred. For {@link NoViableAltException} and
    # {@link LexerNoViableAltException} exceptions, this is the
    # {@link DecisionState} number. For others, it is the state whose outgoing
    # edge we couldn't match.
    @offendingState = -1
    @offendingState = recognizer.state unless recognizer.nil?
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
  def getExpectedTokens
    if not @recognizer.nil?
      return @recognizer.atn.getExpectedTokens(@offendingState, @ctx)
    else
      return nil
    end
  end
end

class LexerNoViableAltException < RecognitionException
  attr_accessor(:startIndex, :deadEndConfigs)

  def initialize(lexer, input, startIndex, deadEndConfigs)
    super(nil, lexer, input, nil)
    @startIndex = startIndex
    @deadEndConfigs = deadEndConfigs
  end

  def to_s
    symbol = ""
    if @startIndex >= 0 and @startIndex < @input.size
      symbol = @input.getText(@startIndex, @startIndex)
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
  def initialize(recognizer, input = nil, startToken = nil, offendingToken = nil, deadEndConfigs = nil, ctx = nil)
    ctx = recognizer.ctx if ctx.nil?
    offendingToken = recognizer.getCurrentToken() if offendingToken.nil?
    startToken = recognizer.getCurrentToken() if startToken.nil?
    input = recognizer.getInputStream() if input.nil?
    super(nil, recognizer, input, ctx)
    # Which configurations did we try at input.index() that couldn't match input.LT(1)?#
    @deadEndConfigs = deadEndConfigs
    # The token object at the start index; the input stream might
    # 	not be buffering tokens so get a reference to it. (At the
    #  time the error occurred, of course the stream needs to keep a
    #  buffer all of the tokens but later we might not have access to those.)
    @startToken = startToken
    @offendingToken = offendingToken
  end
end

# This signifies any kind of mismatched input exceptions such as
#  when the current input does not match the expected token.
#
class InputMismatchException < RecognitionException
  def initialize(recognizer)
    super(nil, recognizer, recognizer.getInputStream(), recognizer.ctx)
    @offendingToken = recognizer.getCurrentToken()
  end
end

# A semantic predicate failed during validation.  Validation of predicates
#  occurs when normally parsing the alternative just like matching a token.
#  Disambiguating predicate evaluation occurs when we test a predicate during
#  prediction.
class FailedPredicateException < RecognitionException
  attr_accessor(:ruleIndex, :predicateIndex, :predicate)

  def initialize(recognizer, predicate = nil, message = nil)
    super(formatMessage(predicate, message), recognizer, recognizer.getInputStream(), recognizer.ctx)
    s = recognizer.interp.atn.states[recognizer.state]
    trans = s.transitions[0]
    if trans.is_a? PredicateTransition
      @ruleIndex = trans.ruleIndex
      @predicateIndex = trans.predIndex
    else
      @ruleIndex = 0
      @predicateIndex = 0
    end
    @predicate = predicate
    @offendingToken = recognizer.getCurrentToken()
  end

  def formatMessage(predicate, message)
    if not message.nil?
      return message
    else
      return "failed predicate: {#{predicate}}?"
    end
  end
end

class ParseCancellationException < CancellationException
end
