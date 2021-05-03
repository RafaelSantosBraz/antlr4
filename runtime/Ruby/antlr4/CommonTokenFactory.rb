# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

#
# This default implementation of {@link TokenFactory} creates
# {@link CommonToken} objects.
#

require_relative "Token"

class TokenFactory
end

class CommonTokenFactory < TokenFactory
  attr_accessor(:copyText)

  def initialize(copyText = false)
    # Indicates whether {@link CommonToken#setText} should be called after
    # constructing tokens to explicitly set the text. This is useful for cases
    # where the input stream might not be able to provide arbitrary substrings
    # of text from the input after the lexer creates a token (e.g. the
    # implementation of {@link CharStream#getText} in
    # {@link UnbufferedCharStream} throws an
    # {@link UnsupportedOperationException}). Explicitly setting the token text
    # allows {@link Token#getText} to be called at any time regardless of the
    # input stream implementation.
    #
    # <p>
    # The default value is {@code false} to avoid the performance and memory
    # overhead of copying text for every token unless explicitly requested.</p>
    #
    @copyText = copyText
  end

  def create(source, type, text, channel, start, stop, line, column)
    t = CommonToken.new(source, type, channel, start, stop)
    t.line = line
    t.column = column
    if not text.nil?
      t.text = text
    elsif @copyText and not source[1].nil?
      t.text = source[1].getText(start, stop)
    end
    t
  end

  def createThin(type, text)
    t = CommonToken.new(CommonToken::EMPTY_SOURCE, type, CommonToken::DEFAULT_CHANNEL, -1, -1)
    t.text = text
    t
  end
end

#
# The default {@link CommonTokenFactory} instance.
#
# <p>
# This token factory does not explicitly copy token text when constructing
# tokens.</p>
#
CommonTokenFactory::DEFAULT = CommonTokenFactory.new
