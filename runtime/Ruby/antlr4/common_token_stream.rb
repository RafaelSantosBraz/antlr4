#
# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#/

require_relative "buffered_token_stream"
require_relative "token"

#
# This class extends {@link BufferedTokenStream} with functionality to filter
# token streams to tokens on a particular channel (tokens where
# {@link Token#getChannel} returns a particular value).
#
# <p>
# This token stream provides access to all tokens by index or when calling
# methods like {@link #getText}. The channel filtering is only used for code
# accessing tokens via the lookahead methods {@link #LA}, {@link #LT}, and
# {@link #LB}.</p>
#
# <p>
# By default, tokens are placed on the default channel
# ({@link Token#DEFAULT_CHANNEL}), but may be reassigned by using the
# {@code ->channel(HIDDEN)} lexer command, or by using an embedded action to
# call {@link Lexer#setChannel}.
# </p>
#
# <p>
# Note: lexer rules which use the {@code ->skip} lexer command or call
# {@link Lexer#skip} do not produce tokens at all, so input text matched by
# such a rule will not be available as part of the token stream, regardless of
# channel.</p>
#/
class CommonTokenStream < BufferedTokenStream
  attr_accessor(:channel)

  def initialize(lexer, channel = Token::DEFAULT_CHANNEL)
    super(lexer)
    @channel = channel
  end

  def adjust_seek_index(i)
    next_token_on_channel(i, @channel)
  end

  def lb(k)
    return nil if k == 0 or (@index - k) < 0
    i = @index
    n = 1
    # find k good tokens looking backwards
    while n <= k
      # skip off-channel tokens
      i = previous_token_on_channel(i - 1, @channel)
      n += 1
    end
    return nil if i < 0
    @tokens[i]
  end

  def lt(k)
    lazy_init()
    return nil if k == 0
    return lb(-k) if k < 0
    i = @index
    n = 1 # we know tokens[pos] is a good one
    # find k good tokens
    while n < k
      # skip off-channel tokens, but make sure to not look past EOF
      i = next_token_on_channel(i + 1, @channel) if sync(i + 1)
      n += 1
    end
    @tokens[i]
  end

  # Count EOF just once.#/
  def get_number_of_on_channel_tokens
    n = 0
    fill()
    (0..(@tokens.size - 1)).each { |i|
      t = @tokens[i]
      n += 1 if t.channel == @channel
      break if t.type == Token::EOF
    }
    n
  end
end
