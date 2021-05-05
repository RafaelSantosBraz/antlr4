# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "lexer_action"

class LexerActionExecutor
  attr_accessor(:lexer_actions, :cached_hash_code)
  #
  # Represents an executor for a sequence of lexer actions which traversed during
  # the matching operation of a lexer rule (token).
  #
  # <p>The executor tracks position information for position-dependent lexer actions
  # efficiently, ensuring that actions appearing only at the end of the rule do
  # not cause bloating of the {@link DFA} created for the lexer.</p>
  #/
  def initialize(lexer_actions = [])
    @lexer_actions = lexer_actions
    #
    # Caches the result of {@link //hashCode} since the hash code is an element
    # of the performance-critical {@link LexerATNConfig//hashCode} operation
    #/
    @cached_hash_code = lexer_actions.hash # "".join([str(la) for la in lexerActions]))
  end

  #
  # Creates a {@link LexerActionExecutor} which encodes the current offset
  # for position-dependent lexer actions.
  #
  # <p>Normally, when the executor encounters lexer actions where
  # {@link LexerAction//isPositionDependent} returns {@code true}, it calls
  # {@link IntStream//seek} on the input {@link CharStream} to set the input
  # position to the <em>end</em> of the current token. This behavior provides
  # for efficient DFA representation of lexer actions which appear at the end
  # of a lexer rule, even when the lexer rule matches a variable number of
  # characters.</p>
  #
  # <p>Prior to traversing a match transition in the ATN, the current offset
  # from the token start index is assigned to all position-dependent lexer
  # actions which have not already been assigned a fixed offset. By storing
  # the offsets relative to the token start index, the DFA representation of
  # lexer actions which appear in the middle of tokens remains efficient due
  # to sharing among tokens of the same length, regardless of their absolute
  # position in the input stream.</p>
  #
  # <p>If the current executor already has offsets assigned to all
  # position-dependent lexer actions, the method returns {@code this}.</p>
  #
  # @param offset The current offset to assign to all position-dependent
  # lexer actions which do not already have offsets assigned.
  #
  # @return {LexerActionExecutor} A {@link LexerActionExecutor} which stores input stream offsets
  # for all position-dependent lexer actions.
  #/
  def fix_offset_before_match(offset)
    updated_lexer_actions = nil
    (0..(@lexer_actions.size - 1)).each { |i|
      if @lexer_actions[i].is_position_dependent and
         not @lexer_actions[i].is_a?(LexerIndexedCustomAction)
        updated_lexer_actions = @lexer_actions.dup if updated_lexer_actions.nil?
        updated_lexer_actions[i] = LexerIndexedCustomAction.new(offset, @lexer_actions[i])
      end
    }
    return self if updated_lexer_actions.nil?
    LexerActionExecutor.new(updated_lexer_actions)
  end

  #
  # Execute the actions encapsulated by this executor within the context of a
  # particular {@link Lexer}.
  #
  # <p>This method calls {@link IntStream//seek} to set the position of the
  # {@code input} {@link CharStream} prior to calling
  # {@link LexerAction//execute} on a position-dependent action. Before the
  # method returns, the input position will be restored to the same position
  # it was in when the method was invoked.</p>
  #
  # @param lexer The lexer instance.
  # @param input The input stream which is the source for the current token.
  # When this method is called, the current {@link IntStream//index} for
  # {@code input} should be the start of the following token, i.e. 1
  # character past the end of the current token.
  # @param startIndex The token start index. This value may be passed to
  # {@link IntStream//seek} to set the {@code input} position to the beginning
  # of the token.
  #/

  def execute(lexer, input, start_index)
    requires_seek = false
    stop_index = input.index
    begin
      (0..(@lexer_actions.size - 1)).each { |i|
        lexer_action = @lexer_actions[i]
        if lexer_action.is_a? LexerIndexedCustomAction
          offset = lexer_action.offset
          input.seek(start_index + offset)
          lexer_action = lexer_action.action
          requires_seek = (start_index + offset) != stop_index
        elsif lexer_action.is_position_dependent
          input.seek(stop_index)
          requires_seek = false
        end
        lexer_action.execute(lexer)
      }
    ensure
      input.seek(stop_index) if requires_seek
    end
  end

  def hash
    @cached_hash_code
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? LexerActionExecutor
    return false if @cached_hash_code != other.cached_hash_code
    return false if @lexer_actions.size != other.lexer_actions.size
    num_actions = @lexer_actions.size
    (0..(num_actions - 1)).each { |idx|
      return false unless @lexer_actions[idx].eql? other.lexer_actions[idx]
    }
    true
  end

  #
  # Creates a {@link LexerActionExecutor} which executes the actions for
  # the input {@code lexerActionExecutor} followed by a specified
  # {@code lexerAction}.
  #
  # @param lexerActionExecutor The executor for actions already traversed by
  # the lexer while matching a token within a particular
  # {@link LexerATNConfig}. If this is {@code null}, the method behaves as
  # though it were an empty executor.
  # @param lexerAction The lexer action to execute after the actions
  # specified in {@code lexerActionExecutor}.
  #
  # @return {LexerActionExecutor} A {@link LexerActionExecutor} for executing the combine actions
  # of {@code lexerActionExecutor} and {@code lexerAction}.
  #/
  def self.append(lexer_action_executor, lexer_action)
    return LexerActionExecutor.new([lexer_action]) if lexer_action_executor.nil?
    lexer_actionss = lexer_action_executor.lexer_actions + [lexer_action]
    LexerActionExecutor.new(lexer_actionss)
  end
end
