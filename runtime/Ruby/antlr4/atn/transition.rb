# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "../token"
require_relative "../interval_set"
require_relative "semantic_context"
require_relative "../utils"

require "ostruct"

# An ATN transition between any two ATN states.  Subclasses define
# atom, set, epsilon, action, predicate, rule transitions.
#
# <p>This is a one way link.  It emanates from a state (usually via a list of
# transitions) and has a target state.</p>
#
# <p>Since we never have to change the ATN transitions once we construct it,
# we can fix these transitions as specific classes. The DFA transitions
# on the other hand need to update the labels as it adds transitions to
# the states. We'll use the term Edge for the DFA to distinguish them from
# ATN transitions.</p>
#/
class Transition

  # constants for serialization

  EPSILON = 1
  RANGE = 2
  RULE = 3
  # e.g., {isType(input.LT(1))}?
  PREDICATE = 4
  ATOM = 5
  ACTION = 6
  # ~(A|B) or ~atom, wildcard, which convert to next 2
  SET = 7
  NOT_SET = 8
  WILDCARD = 9
  PRECEDENCE = 10

  @@serialization_names = [
    "INVALID",
    "EPSILON",
    "RANGE",
    "RULE",
    "PREDICATE",
    "ATOM",
    "ACTION",
    "SET",
    "NOT_SET",
    "WILDCARD",
    "PRECEDENCE",
  ]

  @@serialization_types = OpenStruct.new(
    :epsilon_transition => EPSILON,
    :range_transition => RANGE,
    :rule_transition => RULE,
    :predicate_transition => PREDICATE,
    :atom_transition => ATOM,
    :action_transition => ACTION,
    :set_transition => SET,
    :not_set_transition => NOT_SET,
    :wildcard_transition => WILDCARD,
    :precedence_predicate_transition => PRECEDENCE,
  )

  def self.serialization_names
    @@serialization_names
  end

  def self.serialization_names=(serialization_names)
    @@serialization_names = serialization_names
  end

  def self.serialization_types
    @@serialization_types
  end

  def self.serialization_types=(serialization_types)
    @@serialization_types = serialization_types
  end

  attr_accessor(:target, :is_epsilon, :label)

  def initialize(target)
    # The target of this transition.
    raise(Exception, "target cannot be nil.") if target.nil?
    @target = target
    # Are we epsilon, action, sempred?
    @is_epsilon = false
    @label = nil
  end
end

# TODO: make all transitions sets? no, should remove set edges
class AtomTransition < Transition
  attr_accessor(:serialization_type)

  def initialize(target, label)
    super(target)
    # The token type or character value; or, signifies special label.
    @label_ = label
    @label = make_label()
    @serialization_type = Transition::ATOM
  end

  def make_label
    s = IntervalSet.new
    s.add_one(@label_)
    s
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    @label_ == symbol
  end

  def to_s
    @label_
  end
end

class RuleTransition < Transition
  attr_accessor(:rule_index, :precedence, :follow_state, :serialization_type)

  def initialize(rule_start, rule_index, precedence, follow_state)
    super(rule_start)
    # ptr to the rule definition object for this rule ref
    @rule_index = rule_index
    @precedence = precedence
    # what node to begin computations following ref to rule
    @follow_state = follow_state
    @serialization_type = Transition::RULE
    @is_epsilon = true
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    false
  end
end

class EpsilonTransition < Transition
  attr_accessor(:serialization_type, :outermost_precedence_return)

  def initialize(target, outermost_precedence_return)
    super(target)
    @serialization_type = Transition::EPSILON
    @is_epsilon = true
    @outermost_precedence_return = outermost_precedence_return
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    false
  end

  def to_s
    "epsilon"
  end
end

class RangeTransition < Transition
  attr_accessor(:serialization_type, :start, :stop)

  def initialize(target, start, stop)
    super(target)
    @serialization_type = Transition::RANGE
    @start = start
    @stop = stop
    @label = make_label()
  end

  def make_label
    s = IntervalSet.new
    s.add_range(@start, @stop)
    s
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    symbol >= @start and symbol <= @stop
  end

  def to_s
    "'#{@start.chr(DECODE_ENCODING)}'..'#{@stop.chr(DECODE_ENCODING)}'"
  end
end

class AbstractPredicateTransition < Transition
  def initialize(target)
    super(target)
  end
end

class PredicateTransition < AbstractPredicateTransition
  attr_accessor(:serialization_type, :rule_index, :pred_index, :is_ctx_dependent)

  def initialize(target, rule_index, pred_index, is_ctx_dependent)
    super(target)
    @serialization_type = Transition::PREDICATE
    @rule_index = rule_index
    @pred_index = pred_index
    @is_ctx_dependent = is_ctx_dependent # e.g., $i ref in pred
    @is_epsilon = true
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    false
  end

  def get_predicate
    Predicate.new(@rule_index, @pred_index, @is_ctx_dependent)
  end

  def to_s
    "pred_#{@rule_index}:#{@pred_index}"
  end
end

class ActionTransition < Transition
  attr_accessor(:serialization_type, :rule_index, :action_index, :is_ctx_dependent)

  def initialize(target, rule_index, action_index = -1, is_ctx_dependent = false)
    super(target)
    @serialization_type = Transition::ACTION
    @rule_index = rule_index
    @action_index = action_index
    @is_ctx_dependent = is_ctx_dependent #  e.g., $i ref in pred
    @is_epsilon = true
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    false
  end

  def to_s
    "action_#{@rule_index}:#{@action_index}"
  end
end

# A transition containing a set of values.
class SetTransition < Transition
  attr_accessor(:serialization_type)

  def initialize(target, set = nil)
    super(target)
    @serialization_type = Transition::SET
    if not set.nil?
      @label = set
    else
      @label = IntervalSet.new
      @label.add_one(Token::INVALID_TYPE)
    end
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    @label.include?(symbol)
  end

  def to_s
    @label.to_s
  end
end

class NotSetTransition < SetTransition
  def initialize(target, set = nil)
    super(target, set)
    @serialization_type = Transition::NOT_SET
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    symbol >= min_vocab_symbol and symbol <= max_vocab_symbol and
    not super(symbol, min_vocab_symbol, max_vocab_symbol)
  end

  def to_s
    "~#{super()}"
  end
end

class WildcardTransition < Transition
  attr_accessor(:serialization_type)

  def initialize(target)
    super(target)
    @serialization_type = Transition::WILDCARD
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    symbol >= min_vocab_symbol and symbol <= max_vocab_symbol
  end

  def to_s
    "."
  end
end

class PrecedencePredicateTransition < AbstractPredicateTransition
  attr_accessor(:serialization_type, :precedence)

  def initialize(target, precedence)
    super(target)
    @serialization_type = Transition::PRECEDENCE
    @precedence = precedence
    @is_epsilon = true
  end

  def matches(symbol, min_vocab_symbol, max_vocab_symbol)
    false
  end

  def get_predicate
    PrecedencePredicate.new(@precedence)
  end

  def to_s
    "#{@precedence} >= _p"
  end
end
