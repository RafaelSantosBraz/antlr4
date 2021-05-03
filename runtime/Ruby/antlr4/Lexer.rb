# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "CommonTokenFactory"
require_relative "atn/LexerATNSimulator"
require_relative "InputStream"
require_relative "Recognizer"
require_relative "Token"
require_relative "error/Errors"

# Adapted from Python3 and JavaScript
class TokenSource < Recognizer
end

# A lexer is recognizer that draws input symbols from a character stream.
#  lexer grammars result in a subclass of self object. A Lexer object
#  uses simplified match() and error recovery mechanisms in the interest
#  of speed.
#/
class Lexer < TokenSource
  attr_accessor(:input, :output, :factory, :tokenFactorySourcePair, :token, :tokenStartCharIndex, :tokenStartLine, :tokenStartColumn, :hitEOF, :channel, :type, :modeStack, :mode, :text)

  DEFAULT_MODE = 0
  MORE = -2
  SKIP = -3

  DEFAULT_TOKEN_CHANNEL = Token::DEFAULT_CHANNEL
  HIDDEN = Token::HIDDEN_CHANNEL
  MIN_CHAR_VALUE = 0x0000
  MAX_CHAR_VALUE = 0x10FFFF

  def initialize(input, output = STDOUT)
    @input = input
    @output = output
    @factory = CommonTokenFactory::DEFAULT
    @tokenFactorySourcePair = [self, input]
    @interp = nil # child classes must populate this
    # The goal of all lexer rules/methods is to create a token object.
    #  self is an instance variable as multiple rules may collaborate to
    #  create a single token.  nextToken will return self object after
    #  matching lexer rule(s).  If you subclass to allow multiple token
    #  emissions, then set self to the last token to be matched or
    #  something nonnull so that the auto token emit mechanism will not
    #  emit another token.
    @token = nil
    # What character index in the stream did the current token start at?
    #  Needed, for example, to get the text for current token.  Set at
    #  the start of nextToken.
    @tokenStartCharIndex = -1
    # The line on which the first character of the token resides#/
    @tokenStartLine = -1
    # The character position of first character within the line#/
    @tokenStartColumn = -1
    # Once we see EOF on char stream, next token will be EOF.
    #  If you have DONE : EOF ; then you see DONE EOF.
    @hitEOF = false
    # The channel number for the current token#/
    @channel = Token::DEFAULT_CHANNEL
    # The token type for the current token#/
    @type = Token::INVALID_TYPE
    @modeStack = []
    @mode = DEFAULT_MODE
    # You can set the text for the current token to override what is in
    #  the input char buffer.  Use setText() or can set self instance var.
    #/
    @text = nil
  end

  def reset
    # wack Lexer state variables
    @input.seek(0) unless @input.nil?
    @token = nil
    @type = Token::INVALID_TYPE
    @channel = Token::DEFAULT_CHANNEL
    @tokenStartCharIndex = -1
    @tokenStartColumn = -1
    @tokenStartLine = -1
    @text = nil
    @hitEOF = false
    @mode = Lexer::DEFAULT_MODE
    @modeStack = []
    @interp.reset()
  end

  # Return a token from self source; i.e., match a token on the char
  #  stream.
  def nextToken
    if @input.nil?
      raise IllegalStateException, "nextToken requires a non-null input stream."
    end
    # Mark start location in char stream so unbuffered streams are
    # guaranteed at least have text of current token
    tokenStartMarker = @input.mark()
    begin
      while true
        if @hitEOF
          emitEOF()
          return @token
        end
        @token = nil
        @channel = Token::DEFAULT_CHANNEL
        @tokenStartCharIndex = @input.index
        @tokenStartColumn = @interp.column
        @tokenStartLine = @interp.line
        @text = nil
        continueOuter = false
        while true
          @type = Token::INVALID_TYPE
          ttype = SKIP
          begin
            ttype = @interp.match(@input, @mode)
          rescue LexerNoViableAltException => e
            notifyListeners(e) # report error
            recover(e)
          end
          @hitEOF = true if @input.lA(1) == Token::EOF
          @type = ttype if @type == Token::INVALID_TYPE
          if @type == SKIP
            continueOuter = true
            break
          end
          break if @type != MORE
        end
        next if continueOuter
        emit() if @token.nil?
        return @token
      end
    ensure
      # make sure we release marker after match or
      # unbuffered char stream will keep buffering
      @input.release(tokenStartMarker)
    end
  end

  # Instruct the lexer to skip creating a token for current lexer rule
  #  and look for another token.  nextToken() knows to keep looking when
  #  a lexer rule finishes with token set to SKIP_TOKEN.  Recall that
  #  if token==null at end of any token rule, it creates one for you
  #  and emits it.
  #/
  def skip
    @type = SKIP
  end

  def more
    @type == MORE
  end

  def pushMode(m)
    @output.puts("pushMode #{m}") if @interp.debug
    @modeStack << @mode
    @mode = m
  end

  def popMode
    if @modeStack.size == 0
      raise Exception, "Empty Stack"
    end
    @output.puts("popMode back to #{@modeStack[0..-1]}") if @interp.debug
    @mode = @modeStack.pop()
  end

  # Set the char stream and reset the lexer#/
  def inputStream
    @input
  end

  def inputStream=(input)
    @input = nil
    @tokenFactorySourcePair = [self, @input]
    reset()
    @input = input
    @tokenFactorySourcePair = [self, @input]
  end

  def sourceName
    @input.sourceName
  end

  # By default does not support multiple emits per nextToken invocation
  #  for efficiency reasons.  Subclass and override self method, nextToken,
  #  and getToken (to push tokens into a list and pull from that list
  #  rather than a single variable as self implementation does).
  #/
  def emitToken(token)
    @token = token
  end

  # The standard method called to automatically emit a token at the
  #  outermost lexical rule.  The token object should point into the
  #  char buffer start..stop.  If there is a text override in 'text',
  #  use that to set the token's text.  Override self method to emit
  #  custom Token objects or provide a new factory.
  #/
  def emit
    t = @factory.create(@tokenFactorySourcePair, @type, @text, @channel, @tokenStartCharIndex, getCharIndex() - 1, @tokenStartLine, @tokenStartColumn)
    emitToken(t)
    t
  end

  def emitEOF
    cpos = column()
    lpos = line()
    eof = @factory.create(@tokenFactorySourcePair, Token::EOF, nil, Token::DEFAULT_CHANNEL, @input.index, @input.index - 1, lpos, cpos)
    emitToken(eof)
    eof
  end

  def column
    @interp.column
  end

  def column=(column)
    @interp.column = column
  end

  def line
    @interp.line
  end

  def line=(line)
    @interp.line = line
  end

  # What is the index of the current character of lookahead?#/
  def getCharIndex
    @input.index
  end

  # Return the text matched so far for the current token or any
  #  text override.
  def text
    if not @text.nil?
      return @text
    else
      return @interp.getText(@input)
    end
  end

  # Return a list of all Token objects in input char stream.
  #  Forces load of all tokens. Does not include EOF token.
  #/
  def getAllTokens
    tokens = []
    t = nextToken()
    while t.type != Token::EOF
      tokens << t
      t = nextToken()
    end
    tokens
  end

  def notifyListeners(e)
    start = @tokenStartCharIndex
    stop = @input.index
    text = @input.getText(start, stop)
    msg = "token recognition error at: '#{getErrorDisplay(txt)}'"
    listener = getErrorListenerDispatch()
    listener.syntaxError(self, nil, @tokenStartLine, @tokenStartColumn, msg, e)
  end

  def getErrorDisplay(s)
    buf = ""
    s.each_char { |c|
      buf << getErrorDisplayForChar(c)
    }
    buf
  end

  def getErrorDisplayForChar(c)
    if c[0].ord == Token::EOF
      return "<EOF>"
    elsif c == "\n"
      return "\\n"
    elsif c == "\t"
      return "\\t"
    elsif c == "\r"
      return "\\r"
    else
      return c
    end
  end

  def getCharErrorDisplay(c)
    "'#{getErrorDisplayForChar(c)}'"
  end

  # Lexers can normally match any char in it's vocabulary after matching
  #  a token, so do the easy thing and just kill a character and hope
  #  it all works out.  You can instead use the rule invocation stack
  #  to do sophisticated error recovery if you are in a fragment rule.
  #/
  def recover(re)
    if @input.lA(1) != Token::EOF
      if re.is_a? LexerNoViableAltException
        # skip a char and try again
        @interp.consume(@input)
      else
        # TODO: Do we lose character or line position information?
        @input.consume()
      end
    end
  end
end
