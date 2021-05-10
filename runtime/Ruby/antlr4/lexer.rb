# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "common_token_factory"
require_relative "recognizer"
require_relative "token"
require_relative "error/errors"

class TokenSource
end

# A lexer is recognizer that draws input symbols from a character stream.
#  lexer grammars result in a subclass of self object. A Lexer object
#  uses simplified match() and error recovery mechanisms in the interest
#  of speed.
#/
class Lexer < Recognizer
  attr_accessor(:output)

  DEFAULT_MODE = 0
  MORE = -2
  SKIP = -3

  DEFAULT_TOKEN_CHANNEL = Token::DEFAULT_CHANNEL
  HIDDEN = Token::HIDDEN_CHANNEL
  MIN_CHAR_VALUE = 0x0000
  MAX_CHAR_VALUE = 0x10FFFF

  def initialize(input, output = STDOUT)
    @_input = input
    @output = output
    @_factory = CommonTokenFactory::DEFAULT
    @_token_factory_source_pair = [self, input]
    @_interp = nil # child classes must populate this
    # The goal of all lexer rules/methods is to create a token object.
    #  self is an instance variable as multiple rules may collaborate to
    #  create a single token.  nextToken will return self object after
    #  matching lexer rule(s).  If you subclass to allow multiple token
    #  emissions, then set self to the last token to be matched or
    #  something nonnull so that the auto token emit mechanism will not
    #  emit another token.
    @_token = nil
    # What character index in the stream did the current token start at?
    #  Needed, for example, to get the text for current token.  Set at
    #  the start of nextToken.
    @_token_start_char_index = -1
    # The line on which the first character of the token resides#/
    @_token_start_line = -1
    # The character position of first character within the line#/
    @_token_start_column = -1
    # Once we see EOF on char stream, next token will be EOF.
    #  If you have DONE : EOF ; then you see DONE EOF.
    @_hit_EOF = false
    # The channel number for the current token#/
    @_channel = Token::DEFAULT_CHANNEL
    # The token type for the current token#/
    @_type = Token::INVALID_TYPE
    @_mode_stack = []
    @_mode = DEFAULT_MODE
    # You can set the text for the current token to override what is in
    #  the input char buffer.  Use setText() or can set self instance var.
    #/
    @_text = nil
  end

  def reset
    # wack Lexer state variables
    @_input.seek(0) unless @_input.nil?
    @_token = nil
    @_type = Token::INVALID_TYPE
    @_channel = Token::DEFAULT_CHANNEL
    @_token_start_char_index = -1
    @_token_start_column = -1
    @_token_start_line = -1
    @_text = nil
    @_hit_EOF = false
    @_mode = Lexer::DEFAULT_MODE
    @_mode_stack = []
    @_interp.reset()
  end

  # Return a token from self source; i.e., match a token on the char
  #  stream.
  def next_token
    if @_input.nil?
      raise Exception, "next_token requires a non-null input stream."
    end
    # Mark start location in char stream so unbuffered streams are
    # guaranteed at least have text of current token
    token_start_marker = @_input.mark()
    begin
      while true
        if @_hit_EOF
          emit_EOF()
          return @_token
        end
        @_token = nil
        @_channel = Token::DEFAULT_CHANNEL
        @_token_start_char_index = @_input.index
        @_token_start_column = @_interp.column
        @_token_start_line = @_interp.line
        @_text = nil
        continue_outer = false
        while true
          @_type = Token::INVALID_TYPE
          ttype = SKIP
          begin
            ttype = @_interp.match(@_input, @_mode)
          rescue RecognitionException => e
            notify_listeners(e) # report error
            recover(e)
          end
          @_hit_EOF = true if @_input.la(1) == Token::EOF
          @_type = ttype if @_type == Token::INVALID_TYPE
          if @_type == SKIP
            continue_outer = true
            break
          end
          break if @_type != MORE
        end
        next if continue_outer
        emit() if @_token.nil?
        return @_token
      end
    ensure
      # make sure we release marker after match or
      # unbuffered char stream will keep buffering
      @_input.release(token_start_marker)
    end
  end

  # Instruct the lexer to skip creating a token for current lexer rule
  #  and look for another token.  nextToken() knows to keep looking when
  #  a lexer rule finishes with token set to SKIP_TOKEN.  Recall that
  #  if token==null at end of any token rule, it creates one for you
  #  and emits it.
  #/
  def skip
    @_type = SKIP
  end

  def more
    @_type == MORE
  end

  def mode(m)
    @_mode = m
  end

  def push_mode(m)
    @output.puts("pushMode #{m}") if @_interp.debug
    @_mode_stack << @_mode
    @_mode = m
  end

  def pop_mode
    if @_mode_stack.size == 0
      raise Exception, "Empty Stack"
    end
    @output.puts("popMode back to #{@_mode_stack[0..-1]}") if @_interp.debug
    @_mode = @_mode_stack.pop()
  end

  def input_stream
    @_input
  end

  # Set the char stream and reset the lexer#/
  def input_stream(input)
    @_input = nil
    @_token_factory_source_pair = [self, @_input]
    reset()
    @_input = input
    @_token_factory_source_pair = [self, @_input]
  end

  def source_name
    @_input.source_name
  end

  # By default does not support multiple emits per nextToken invocation
  #  for efficiency reasons.  Subclass and override self method, nextToken,
  #  and getToken (to push tokens into a list and pull from that list
  #  rather than a single variable as self implementation does).
  #/
  def emit_token(token)
    @_token = token
  end

  # The standard method called to automatically emit a token at the
  #  outermost lexical rule.  The token object should point into the
  #  char buffer start..stop.  If there is a text override in 'text',
  #  use that to set the token's text.  Override self method to emit
  #  custom Token objects or provide a new factory.
  #/
  def emit
    t = @_factory.create(@_token_factory_source_pair, @_type, @_text,
                         @_channel, @_token_start_char_index, get_char_index() - 1,
                         @_token_start_line, @_token_start_column)
    emit_token(t)
    t
  end

  def emit_EOF
    cpos = column()
    lpos = line()
    eof = @_factory.create(@_token_factory_source_pair, Token::EOF, nil,
                           Token::DEFAULT_CHANNEL, @_input.index,
                           @_input.index - 1, lpos, cpos)
    emit_token(eof)
    eof
  end

  def type
    @_type
  end

  def type=(type)
    @_type = type
  end

  def column
    @_interp.column
  end

  def column=(column)
    @_interp.column = column
  end

  def line
    @_interp.line
  end

  def line=(line)
    @_interp.line = line
  end

  # What is the index of the current character of lookahead?#/
  def get_char_index
    @_input.index
  end

  # Return the text matched so far for the current token or any
  #  text override.
  def text
    if not @_text.nil?
      return @_text
    else
      return @_interp.get_text(@_input)
    end
  end

  def text=(text)
    @_text = text
  end

  # Return a list of all Token objects in input char stream.
  #  Forces load of all tokens. Does not include EOF token.
  #/
  def get_all_tokens
    tokens = []
    t = next_token()
    while t.type != Token::EOF
      tokens << t
      t = next_token()
    end
    tokens
  end

  def notify_listeners(e)
    start = @_token_start_char_index
    stop = @_input.index
    text = @_input.get_text(start, stop)
    msg = "token recognition error at: '#{get_error_display(txt)}'"
    listener = get_error_listener_dispatch()
    listener.syntax_error(self, nil, @_token_start_line, @_token_start_column,
                          msg, e)
  end

  def get_error_display(s)
    buf = ""
    s.each_char { |c|
      buf << get_error_display_for_char(c)
    }
    buf
  end

  def get_error_display_for_char(c)
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

  def get_char_error_display(c)
    "'#{get_error_display_for_char(c)}'"
  end

  # Lexers can normally match any char in it's vocabulary after matching
  #  a token, so do the easy thing and just kill a character and hope
  #  it all works out.  You can instead use the rule invocation stack
  #  to do sophisticated error recovery if you are in a fragment rule.
  #/
  def recover(re)
    if @_input.la(1) != Token::EOF
      if re.is_a? LexerNoViableAltException
        # skip a char and try again
        @_interp.consume(@_input)
      else
        # TODO: Do we lose character or line position information?
        @_input.consume()
      end
    end
  end
end
