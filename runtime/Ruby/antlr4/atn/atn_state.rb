# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

INITIAL_NUM_TRANSITIONS = 4

# The following images show the relation of states and
# {@link ATNState//transitions} for various grammar constructs.
#
# <ul>
#
# <li>Solid edges marked with an &//0949; indicate a required
# {@link EpsilonTransition}.</li>
#
# <li>Dashed edges indicate locations where any transition derived from
# {@link Transition} might appear.</li>
#
# <li>Dashed nodes are place holders for either a sequence of linked
# {@link BasicState} states or the inclusion of a block representing a nested
# construct in one of the forms below.</li>
#
# <li>Nodes showing multiple outgoing alternatives with a {@code ...} support
# any number of alternatives (one or more). Nodes without the {@code ...} only
# support the exact number of alternatives shown in the diagram.</li>
#
# </ul>
#
# <h2>Basic Blocks</h2>
#
# <h3>Rule</h3>
#
# <embed src="images/Rule.svg" type="image/svg+xml"/>
#
# <h3>Block of 1 or more alternatives</h3>
#
# <embed src="images/Block.svg" type="image/svg+xml"/>
#
# <h2>Greedy Loops</h2>
#
# <h3>Greedy Closure: {@code (...)*}</h3>
#
# <embed src="images/ClosureGreedy.svg" type="image/svg+xml"/>
#
# <h3>Greedy Positive Closure: {@code (...)+}</h3>
#
# <embed src="images/PositiveClosureGreedy.svg" type="image/svg+xml"/>
#
# <h3>Greedy Optional: {@code (...)?}</h3>
#
# <embed src="images/OptionalGreedy.svg" type="image/svg+xml"/>
#
# <h2>Non-Greedy Loops</h2>
#
# <h3>Non-Greedy Closure: {@code (...)*?}</h3>
#
# <embed src="images/ClosureNonGreedy.svg" type="image/svg+xml"/>
#
# <h3>Non-Greedy Positive Closure: {@code (...)+?}</h3>
#
# <embed src="images/PositiveClosureNonGreedy.svg" type="image/svg+xml"/>
#
# <h3>Non-Greedy Optional: {@code (...)??}</h3>
#
# <embed src="images/OptionalNonGreedy.svg" type="image/svg+xml"/>
#/
class ATNState

  # constants for serialization
  INVALID_TYPE = 0
  BASIC = 1
  RULE_START = 2
  BLOCK_START = 3
  PLUS_BLOCK_START = 4
  STAR_BLOCK_START = 5
  TOKEN_START = 6
  RULE_STOP = 7
  BLOCK_END = 8
  STAR_LOOP_BACK = 9
  STAR_LOOP_ENTRY = 10
  PLUS_LOOP_BACK = 11
  LOOP_END = 12

  SERIALIZATION_NAMES = [
    "INVALID",
    "BASIC",
    "RULE_START",
    "BLOCK_START",
    "PLUS_BLOCK_START",
    "STAR_BLOCK_START",
    "TOKEN_START",
    "RULE_STOP",
    "BLOCK_END",
    "STAR_LOOP_BACK",
    "STAR_LOOP_ENTRY",
    "PLUS_LOOP_BACK",
    "LOOP_END",
  ]

  INVALID_STATE_NUMBER = -1

  attr_accessor(:atn, :state_number, :state_type, :rule_index,
                :epsilon_only_transitions, :transitions, :next_token_with_rule)

  def initialize
    # Which ATN are we in?
    @atn = nil
    @state_number = ATNState::INVALID_STATE_NUMBER
    @state_type = nil
    @rule_index = 0 # at runtime, we don't have Rule objects
    @epsilon_only_transitions = false
    # Track the transitions emanating from this ATN state.
    @transitions = []
    # Used to cache lookahead during parsing, not used during construction
    @next_token_with_rule = nil
  end

  def to_s
    @state_number.to_s
  end

  def eql?(other)
    return (@state_number == other.state_number) if other.is_a? ATNState
    false
  end

  def is_non_greedy_exit_state
    false
  end

  def add_transition(trans, index = -1)
    if @transitions.size == 0
      @epsilon_only_transitions = trans.is_epsilon
    elsif @epsilon_only_transitions != trans.is_epsilon
      @epsilon_only_transitions = false
    end
    if index == 1
      @transitions << trans
    else
      @transitions[index] = trans
    end
  end
end

class BasicState < ATNState
  def initialize
    @state_type = ATNState::BASIC
  end
end

class DecisionState < ATNState
  attr_accessor(:decision, :non_greedy)

  def initialize
    @decision = -1
    @non_greedy = false
  end
end

# The start of a regular {@code (...)} block
class BlockStartState < DecisionState
  attr_accessor(:end_state)

  def initialize
    @end_state = nil
  end
end

class BasicBlockStartState < BlockStartState
  def initialize
    @state_type = ATNState::BLOCK_START
  end
end

# Terminal node of a simple {@code (a|b|c)} block
class BlockEndState < ATNState
  attr_accessor(:start_state)

  def initialize
    @state_type = ATNState::BLOCK_END
    @start_state = nil
  end
end

# The last node in the ATN for a rule, unless that rule is the start symbol.
# In that case, there is one transition to EOF. Later, we might encode
# references to all calls to this rule to compute FOLLOW sets for
# error handling
#/
class RuleStopState < ATNState
  def initialize
    @state_type = ATNState::RULE_STOP
  end
end

class RuleStartState < ATNState
  attr_accessor(:stop_state, :is_precedence_rule)

  def initialize
    @state_type = ATNState::RULE_START
    @stop_state = nil
    @is_precedence_rule = false
  end
end

# Decision state for {@code A+} and {@code (A|B)+}.  It has two transitions:
# one to the loop back to start of the block and one to exit.
#/
class PlusLoopbackState < DecisionState
  def initialize
    @state_type = ATNState::PLUS_LOOP_BACK
  end
end

# Start of {@code (A|B|...)+} loop. Technically a decision state, but
# we don't use for code generation; somebody might need it, so I'm defining
# it for completeness. In reality, the {@link PlusLoopbackState} node is the
# real decision-making note for {@code A+}
#/
class PlusBlockStartState < BlockStartState
  attr_accessor(:loop_back_state)

  def initialize
    @state_type = ATNState::PLUS_BLOCK_START
    @loop_back_state = nil
  end
end

# The block that begins a closure loop
class StarBlockStartState < BlockStartState
  def initialize
    @state_type = ATNState::STAR_BLOCK_START
  end
end

class StarLoopbackState < ATNState
  def initialize
    @state_type = ATNState::STAR_LOOP_BACK
  end
end

class StarLoopEntryState < DecisionState
  attr_accessor(:loop_back_state, :is_precedence_decision)

  def initialize
    @state_type = ATNState::STAR_LOOP_ENTRY
    @loop_back_state = nil
    # Indicates whether this state can benefit from a precedence DFA during SLL
    # decision making.
    @is_precedence_decision = nil
  end
end

# Mark the end of a * or + loop
class LoopEndState < ATNState
  attr_accessor(:loop_back_state)

  def initialize
    @state_type = ATNState::LOOP_END
    @loop_back_state = nil
  end
end

# The Tokens rule start state linking to each lexer rule start state
class TokenStartState < DecisionState
  def initialize
    @state_type = ATNState::TOKEN_START
  end
end
