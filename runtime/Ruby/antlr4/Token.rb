# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

# A token has properties: text, type, line, character position in the line
# (so we can ignore tabs), token channel, index, and source from which
# we obtained this token.
class Token
  attr_accessor(:source, :type, :channel, :start, :stop, :tokenIndex, :line, :column, :text)

  INVALID_TYPE = 0

  # During lookahead operations, this "token" signifies we hit rule end ATN state
  # and did not follow it despite needing to.
  EPSILON = -2

  MIN_USER_TOKEN_TYPE = 1

  EOF = -1

  # All tokens go to the parser (unless skip() is called in that rule)
  # on a particular "channel".  The parser tunes to a particular channel
  # so that whitespace etc... can go to the parser on a "hidden" channel.

  DEFAULT_CHANNEL = 0

  # Anything on different channel than DEFAULT_CHANNEL is not parsed
  # by parser.

  HIDDEN_CHANNEL = 1

  def initialize
    @source = nil
    @type = nil # token type of the token
    @channel = nil # The parser ignores everything not on DEFAULT_CHANNEL
    @start = nil # optional; return -1 if not implemented.
    @stop = nil  # optional; return -1 if not implemented.
    @tokenIndex = nil # from 0..n-1 of the token object in the input stream
    @line = nil # line=1..n of the 1st character
    @column = nil # beginning of the line at which it occurs, 0..n-1
    @text = nil # text of the token.
  end

  def getTokenSource
    @source[0]
  end

  def getInputStream
    @source[1]
  end
end

class CommonToken < Token

  # An empty {@link Pair} which is used as the default value of
  # {@link #source} for tokens that do not have a source.
  EMPTY_SOURCE = [None, None]

  def initialize(source = EMPTY_SOURCE, type = nil, channel = DEFAULT_CHANNEL, start = -1, stop = -1)
    @source = source
    @type = type
    @channel = channel
    @start = start
    @stop = stop
    @tokenIndex = -1
    if not source[0].nil?
      @line = source[0].line
      @column = source[0].column
    else
      @column = -1
    end

    # Constructs a new {@link CommonToken} as a copy of another {@link Token}.
    #
    # <p>
    # If {@code oldToken} is also a {@link CommonToken} instance, the newly
    # constructed token will share a reference to the {@link #text} field and
    # the {@link Pair} stored in {@link #source}. Otherwise, {@link #text} will
    # be assigned the result of calling {@link #getText}, and {@link #source}
    # will be constructed from the result of {@link Token#getTokenSource} and
    # {@link Token#getInputStream}.</p>
    #
    # @param oldToken The token to copy.
    #
    def clone
      t = CommonToken.new(@source, @type, @channel, @start, @stop)
      t.tokenIndex = @tokenIndex
      t.line = @line
      t.column = @column
      t.text = @text
      t
    end

    def text
      return @text unless @text.nil?
      input = getInputStream()
      return nil if input.nil?
      n = input.size
      if @start < n and @stop < n
        return input.getText(@start, @stop)
      else
        return "<EOF>"
      end
    end
  end

  def to_s
    txt = @text
    if not txt.nil?
      txt = txt.gsub(/\n/, "\\n").gsub(/\r/, "\\r").gsub(/\t/, "\\t")
    else
      txt = "<no text>"
    end
    "[@#{@tokenIndex},#{@start}:#{@stop}='#{txt}',<#{@type}>#{@channel > 0 ? ",channel=#{@channel}" : ""},#{@line}:#{@column}]"
  end
end
