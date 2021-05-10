# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "token"
require_relative "lexer"
require_relative "interval_set"

# this is just to keep meaningful parameter types to Parser
class TokenStream
end

# This implementation of {@link TokenStream} loads tokens from a
# {@link TokenSource} on-demand, and places the tokens in a buffer to provide
# access to any previous token by index.
#
# <p>
# This token stream ignores the value of {@link Token#getChannel}. If your
# parser requires the token stream filter tokens to only those on a particular
# channel, such as {@link Token#DEFAULT_CHANNEL} or
# {@link Token#HIDDEN_CHANNEL}, use a filtering token stream such a
# {@link CommonTokenStream}.</p>
class BufferedTokenStream < TokenStream
  attr_accessor(:token_source, :tokens, :index, :fetched_EOF)

  def initialize(token_source)
    # The {@link TokenSource} from which tokens for this stream are fetched.
    @token_source = token_source
    # A collection of all tokens fetched from the token source. The list is
    # considered a complete view of the input once {@link #fetchedEOF} is set
    # to {@code true}.
    @tokens = []
    # The index into {@link #tokens} of the current token (next token to
    # {@link #consume}). {@link #tokens}{@code [}{@link #p}{@code ]} should be
    # {@link #LT LT(1)}.
    #
    # <p>This field is set to -1 when the stream is first constructed or when
    # {@link #setTokenSource} is called, indicating that the first token has
    # not yet been fetched from the token source. For additional information,
    # see the documentation of {@link IntStream} for a description of
    # Initializing Methods.</p>
    @index = -1
    # Indicates whether the {@link Token#EOF} token has been fetched from
    # {@link #tokenSource} and added to {@link #tokens}. This field improves
    # performance for the following cases:
    #
    # <ul>
    # <li>{@link #consume}: The lookahead check in {@link #consume} to prevent
    # consuming the EOF symbol is optimized by checking the values of
    # {@link #fetchedEOF} and {@link #p} instead of calling {@link #LA}.</li>
    # <li>{@link #fetch}: The check to prevent adding multiple EOF symbols into
    # {@link #tokens} is trivial with this field.</li>
    # <ul>
    @fetched_EOF = false
  end

  def mark
    0
  end

  def release(marker)
    # no resources to release
  end

  def reset
    seek(0)
  end

  def seek(index)
    lazyInit()
    @index = adjustSeekIndex(index)
  end

  def get(index)
    lazy_init()
    @tokens[index]
  end

  def consume
    skip_eof_check = false
    if @index > 0
      if @fetched_EOF
        # the last token in tokens is EOF. skip check if p indexes any
        # fetched token except the last.
        skip_eof_check = @index < @tokens.size - 1
      else
        # no EOF token in tokens. skip check if p indexes a fetched token.
        skip_eof_check = @index < @tokens.size
      end
    else
      # not yet initialized
      skip_eof_check = false
    end
    if not skip_eof_check and la(1) == Token::EOF
      raise Exception, "cannot consume EOF"
    end
    if sync(@index + 1)
      @index = adjust_seek_index(@index + 1)
    end
  end

  # Make sure index {@code i} in tokens has a token.
  #
  # @return {@code true} if a token is located at index {@code i}, otherwise
  #    {@code false}.
  # @see #get(int i)
  #/
  def sync(i)
    n = i - @tokens.size + 1 # how many more elements we need?
    if n > 0
      fetched = fetch(n)
      return fetched >= n
    end
    true
  end

  # Add {@code n} elements to buffer.
  #
  # @return The actual number of elements added to the buffer.
  #/
  def fetch(n)
    return 0 if @fetched_EOF
    (0..(n - 1)).each { |i|
      t = @token_source.next_token()
      t.token_index = @tokens.size
      @tokens << t
      if t.type == Token::EOF
        @fetched_EOF = true
        return i + 1
      end
    }
    n
  end

  # Get all tokens from start..stop inclusively#/
  def get_tokens(start, stop, types = nil)
    return nil if start < 0 or stop < 0
    lazy_init()
    subset = []
    if stop >= @tokens.size
      stop = @tokens.size - 1
    end
    (start..(stop - 1)).each { |i|
      t = @tokens[i]
      break if t.type == Token::EOF
      subset << t if types.nil? or types.include?(t.type)
    }
    subset
  end

  def la(i)
    lt(i).type
  end

  def lb(k)
    return nil if (@index - k) < 0
    @tokens[@index - k]
  end

  def lt(k)
    lazy_init()
    return nil if k == 0
    return lb(-k) if k < 0
    i = @index + k - 1
    sync(i)
    return @tokens[-1] if i >= @tokens.size
    @tokens[i]
  end

  # Allowed derived classes to modify the behavior of operations which change
  # the current stream position by adjusting the target token index of a seek
  # operation. The default implementation simply returns {@code i}. If an
  # exception is thrown in this method, the current stream index should not be
  # changed.
  #
  # <p>For example, {@link CommonTokenStream} overrides this method to ensure that
  # the seek target is always an on-channel token.</p>
  #
  # @param i The target token index.
  # @return The adjusted target token index.
  def adjust_seek_index(i)
    i
  end

  def lazy_init
    setup() if @index == -1
  end

  def setup
    sync(0)
    @index = adjust_seek_index(0)
  end

  # Reset this token stream by setting its token source.#/
  def set_token_source(token_source)
    @token_source = token_source
    @tokens = []
    @index = -1
    @fetched_EOF = false
  end

  # Given a starting index, return the index of the next token on channel.
  #  Return i if tokens[i] is on channel.  Return -1 if there are no tokens
  #  on channel between i and EOF.
  #/
  def next_token_on_channel(i, channel)
    sync(i)
    return -1 if i >= @tokens.size
    token = @tokens[i]
    while token.channel != channel
      return -1 if token.type == Token::EOF
      i += 1
      sync(i)
      token = @tokens[i]
    end
    i
  end

  # Given a starting index, return the index of the previous token on channel.
  #  Return i if tokens[i] is on channel. Return -1 if there are no tokens
  #  on channel between i and 0.
  def previous_token_on_channel(i, channel)
    while i >= 0 and @tokens[i].channel != channel
      i -= 1
    end
    i
  end

  # Collect all tokens on specified channel to the right of
  #  the current token up until we see a token on DEFAULT_TOKEN_CHANNEL or
  #  EOF. If channel is -1, find any non default channel token.
  def get_hidden_tokens_to_right(token_index, channel = -1)
    lazy_init()
    if token_index < 0 or token_index >= @tokens.size
      raise Exception, "#{token_index} not in 0..#{@tokens.size - 1}"
    end
    next_on_channel = next_token_on_channel(token_index + 1, Lexer::DEFAULT_TOKEN_CHANNEL)
    from_ = token_index + 1
    # if none onchannel to right, nextOnChannel=-1 so set to = last token
    if nextOnChannel == -1
      to = @tokens.size - 1
    else
      to = next_on_channel
    end
    filter_for_channel(from_, to, channel)
  end

  def filter_for_channel(left, right, channel)
    hidden = []
    (left..right).each { |i|
      t = @tokens[i]
      if channel == -1
        hidden << t if t.channel != Lexer::DEFAULT_TOKEN_CHANNEL
      elsif t.channel == channel
        hidden << t
      end
    }
    return nil if hidden.size == 0
    hidden
  end

  def get_source_name
    @token_source.get_source_name()
  end

  # Get the text of all tokens in this buffer.#/
  def get_text(interval = nil)
    lazy_init()
    fill()
    if interval.nil?
      interval = Interval.new(0, @tokens.size - 1)
    end
    start = interval.start
    if start.is_a? Token
      start = start.token_index
    end
    stop = interval.stop
    if stop.is_a? Token
      stop = stop.token_index
    end
    return "" if start.nil? or stop.nil? or start < 0 or stop < 0 or stop < start
    if stop >= @tokens.size
      stop = @tokens.size - 1
    end
    s = ""
    (start..stop).each { |i|
      t = @tokens[i]
      break if t.type == Token::EOF
      s << t.text
    }
    s
  end

  # Get all tokens from lexer until EOF#/
  def fill
    lazy_init()
    while fetch(1000) == 1000
      next
    end
  end
end
