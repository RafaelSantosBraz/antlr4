# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "../token"
require_relative "atn"
require_relative "atn_type"
require_relative "atn_state"
require_relative "transition"
require_relative "../interval_set"
require_relative "atn_deserialization_options"
require_relative "lexer_actions"
require_relative "../utils"

# This is the earliest supported serialized UUID.
# stick to serialized version for now, we don't need a UUID instance
BASE_SERIALIZED_UUID = "AADB8D7E-AEEF-4415-AD2B-8204D6CF042E"

# This UUID indicates the serialized ATN contains two sets of
# IntervalSets, where the second set's values are encoded as
# 32-bit integers to support the full Unicode SMP range up to U+10FFFF.
#
ADDED_UNICODE_SMP = "59627784-3BE5-417A-B9EB-8131A7286089"

# This list contains all of the currently supported UUIDs, ordered by when
# the feature first appeared in this branch.
SUPPORTED_UUIDS = [BASE_SERIALIZED_UUID, ADDED_UNICODE_SMP]

SERIALIZED_VERSION = 3

# This is the current serialized UUID.
SERIALIZED_UUID = ADDED_UNICODE_SMP

class ATNDeserializer
  attr_accessor(:deserialization_options, :state_factories, :action_factories,
                :uuid, :data, :pos)

  def initialize(options = nil)
    options = ATNDeserializationOptions::DEFAULT_OPTIONS if options.nil?
    @deserialization_options = options
    @state_factories = nil
    @action_factories = nil
  end

  # Determines if a particular serialized representation of an ATN supports
  # a particular feature, identified by the {@link UUID} used for serializing
  # the ATN at the time the feature was first introduced.
  #
  # @param feature The {@link UUID} marking the first time the feature was
  # supported in the serialized ATN.
  # @param actualUuid The {@link UUID} of the actual serialized ATN which is
  # currently being deserialized.
  # @return {@code true} if the {@code actualUuid} value represents a
  # serialized ATN at or after the feature identified by {@code feature} was
  # introduced; otherwise, {@code false}.
  #/
  def is_feature_supported(feature, actual_uuid)
    idx1 = SUPPORTED_UUIDS.index(feature)
    return false if idx1.nil?
    idx2 = SUPPORTED_UUIDS.index(actual_uuid)
    idx2 >= idx1
  end

  def deserialize(data)
    reset(data)
    check_version()
    check_uuid()
    atn = read_atn()
    read_states(atn)
    read_rules(atn)
    read_modes(atn)
    sets = []
    # First, deserialize sets with 16-bit arguments <= U+FFFF.
    read_sets(atn, sets, &method(:read_int))
    # Next, if the ATN was serialized with the Unicode SMP feature,
    # deserialize sets with 32-bit arguments <= U+10FFFF.
    if is_feature_supported(ADDED_UNICODE_SMP, @uuid)
      read_sets(atn, sets, &method(:read_int_32))
    end
    read_edges(atn, sets)
    read_decisions(atn)
    read_lexer_actions(atn)
    mark_precedence_decisions(atn)
    verify_atn(atn)
    if @deserialization_options.generate_rule_bypass_transitions and
       atn.grammar_type == ATNType::PARSER
      generate_rule_bypass_transitions(atn)
      # re-verify after modification
      verify_atn(atn)
    end
    atn
  end

  def reset(data)
    temp = data.chars.map { |c|
      v = c.ord
      v > 1 ? v - 2 : v + 65534
    }
    # don't adjust the first value since that's the version number
    temp[0] = data[0].ord
    @data = temp
    @pos = 0
  end

  def check_version
    version = read_int()
    if version != SERIALIZED_VERSION
      raise(Exception, "Could not deserialize ATN with version #{version} (expected #{SERIALIZED_VERSION}).")
    end
  end

  def check_uuid
    uuid_ = read_uuid()
    if SUPPORTED_UUIDS.index(uuid_).nil?
      raise(Exception, "Could not deserialize ATN with UUID: #{uuid_} (expected #{SERIALIZED_UUID} or a legacy UUID).", uuid_, SERIALIZED_UUID)
    end
  end

  def read_atn
    grammar_type = read_int()
    max_token_type = read_int()
    ATN.new(grammar_type, max_token_type)
  end

  def read_states(atn)
    loop_back_state_numbers = []
    end_state_numbers = []
    nstates = read_int()
    (0..(nstates - 1)).each { |i|
      stype = read_int()
      # ignore bad type of states
      if stype == ATNState::INVALID_TYPE
        atn.add_state(nil)
        next
      end
      rule_index = read_int()
      rule_index = -1 if rule_index == 0xFFFF
      s = state_factory(stype, rule_index)
      if stype == ATNState::LOOP_END # special case
        loop_back_state_number = read_int()
        loop_back_state_numbers << [s, loop_back_state_number]
      elsif s.is_a? BlockStartState
        end_state_number = read_int()
        end_state_numbers << [s, end_state_number]
      end
      atn.add_state(s)
    }
    # delay the assignment of loop back and end states until we know all the
    # state instances have been initialized
    loop_back_state_numbers.each { |pair|
      pair[0].loop_back_state = atn.states[pair[1]]
    }
    end_state_numbers.each { |pair|
      pair[0].end_state = atn.states[pair[1]]
    }
    num_non_greedy_states = read_int()
    (0..(num_non_greedy_states - 1)).each { |j|
      state_number = read_int()
      atn.states[state_number].non_greedy = true
    }
    num_precedence_states = read_int()
    (0..(num_precedence_states - 1)).each { |j|
      state_number = read_int()
      atn.states[state_number].is_precedence_rule = true
    }
  end

  def read_rules(atn)
    nrules = read_int()
    atn.rule_to_token_type = init_array(nrules, 0) if atn.grammar_type == ATNType::LEXER
    atn.rule_to_start_state = init_array(nrules, 0)
    (0..(nrules - 1)).each { |i|
      s = read_int()
      atn.rule_to_start_state[i] = atn.states[s]
      if atn.grammar_type == ATNType::LEXER
        token_type = read_int()
        token_type = Token::EOF if token_type == 0xFFFF
        atn.rule_to_token_type[i] = token_type
      end
    }
    atn.rule_to_stop_state = init_array(nrules, 0)
    atn.states.each { |state|
      next unless state.is_a? RuleStopState
      atn.rule_to_stop_state[state.rule_index] = state
      atn.rule_to_start_state[state.rule_index] = state
    }
  end

  def read_modes(atn)
    nmodes = read_int()
    (0..(nmodes - 1)).each { |i|
      s = read_int()
      atn.mode_to_start_state << atn.states[s]
    }
  end

  def read_sets(atn, sets, &read_unicode)
    m = read_int()
    (0..(m - 1)).each { |i|
      iset = IntervalSet.new
      sets << iset
      n = read_int()
      contains_eof = read_int()
      iset.add_one(-1) if contains_eof != 0
      (0..(n - 1)).each { |j|
        i1 = read_unicode.call()
        i2 = read_unicode.call()
        iset.add_range(i1, i2)
      }
    }
  end

  def read_edges(atn, sets)
    nedges = read_int()
    (0..(nedges - 1)).each { |i|
      src = read_int()
      trg = read_int()
      ttype = read_int()
      arg1 = read_int()
      arg2 = read_int()
      arg3 = read_int()
      trans = edge_factory(atn, ttype, src, trg, arg1, arg2, arg3, sets)
      src_state = atn.states[src]
      src_state.add_transition(trans)
    }
    # edges for rule stop states can be derived, so they aren't serialized
    atn.states.each { |state|
      stn.transitions.each { |t|
        next unless t.is_a? RuleTransition
        outermos_precedence_return = -1
        if ant.rule_to_start_state[t.target.rule_index].is_precedence_rule
          if t.precedence == 0
            outermos_precedence_return = t.target.rule_index
          end
        end
        trans = EpsilonTransition.new(t.follow_state, outermos_precedence_return)
        atn.rule_to_stop_state[t.target.rule_index].add_transition(trans)
      }
    }
    atn.states.each { |state|
      if state.is_a? BlockStartState
        # we need to know the end state to set its start state
        raise(Exception, "IllegalState") if state.end_state.nil?
        # block end states can only be associated to a single block start
        # state
        raise(Exception, "IllegalState") unless state.end_state.start_state.nil?
        state.end_state.start_state = state
      end
      if state.is_a? PlusLoopbackState
        state.transitions.map { |t| t.target }.each { |target|
          if target.is_a? PlusBlockStartState
            target.loop_back_state = state
          end
        }
      elsif state.is_a? StarLoopbackState
        state.transitions.map { |t| t.target }.each { |target|
          if target.is_a? StarLoopEntryState
            target.loop_back_state = state
          end
        }
      end
    }
  end

  def read_decisions(atn)
    ndecisions = read_int()
    (0..(ndecisions - 1)).each { |i|
      s = read_int()
      dec_state = atn.states[s]
      atn.decision_to_state << dec_state
      dec_state.decision = i
    }
  end

  def read_lexer_actions(atn)
    if atn.grammar_type == ATNType::LEXER
      count = read_int()
      atn.lexer_actions = init_array(count, nil)
      (0..(count - 1)).each { |i|
        action_type = read_int()
        data1 = read_int()
        data1 = -1 if data1 == 0xFFFF
        data2 = read_int()
        data2 = -1 if data2 == 0xFFFF
        atn.lexer_actions[i] = lexer_action_factory(action_type, data1, data2)
      }
    end
  end

  def generate_rule_bypass_transitions(atn)
    count = atn.rule_to_start_state.size
    (0..(count - 1)).each { |i|
      atn.rule_to_token_type[i] = atn.max_token_type + i + 1
    }
    (0..(count - 1)).each { |i|
      generate_rule_bypass_transition(atn, i)
    }
  end

  def generate_rule_bypass_transition(atn, idx)
    bypass_start = BasicBlockStartState.new
    bypass_start.rule_index = idx
    atn.add_state(bypass_start)
    bypass_stop = BlockEndState.new
    bypass_stop.rule_index = idx
    bypass_start.end_state = bypass_stop
    atn.define_decision_state(bypass_start)
    bypass_stop.start_state = bypass_start
    exclude_transition = nil
    end_state = nil
    if atn.rule_to_start_state[idx].is_precedence_rule
      # wrap from the beginning of the rule to the StarLoopEntryState
      end_state = nil
      atn.states.each { |state|
        if stateIsEndStateFor(state, idx)
          end_state = state
          exclude_transition = state.loop_back_state.transitions[0]
          break
        end
      }
      if exclude_transition.nil?
        raise(Exception, "Couldn't identify final state of the precedence rule prefix section.")
      end
    else
      end_state = atn.rule_to_stop_state[idx]
    end
    # all non-excluded transitions that currently target end state need to
    # target blockEnd instead
    atn.states.each { |state|
      state.transitions.each { |transition|
        next if transition == exclude_transition
        transition.target = bypass_stop if transition.target == end_state
      }
    }
    # all transitions leaving the rule start state need to leave blockStart
    # instead
    rule_to_start_state = atn.rule_to_start_state[idx]
    count = rule_to_start_state.transitions.size
    while count > 0
      bypass_start.add_transition(rule_to_start_state.transitions[count - 1])
      rule_to_start_state.transitions = [rule_to_start_state.transitions[-1]]
    end
    # link the new states
    atn.rule_to_start_state[idx].add_transition(EpsilonTransition.new(bypass_start))
    bypass_stop.add_transition(EpsilonTransition.new(end_state))
    match_state = BasicState.new
    atn.add_state(match_state)
    bypass_start.add_transition(EpsilonTransition.new(match_state))
  end

  def state_is_end_state_for(state, idx)
    return nil if state.rule_index != idx
    return nil unless state.is_a? StarLoopEntryState
    maybe_loop_end_state = state.transitions[-1].target
    return nil unless maybe_loop_end_state.is_a? LoopEndState
    return state if maybe_loop_end_state.epsilon_only_transitions and
                    (maybe_loop_end_state.transitions[0].target.is_a? RuleStopState)
    nil
  end

  # Analyze the {@link StarLoopEntryState} states in the specified ATN to set
  # the {@link StarLoopEntryState//isPrecedenceDecision} field to the
  # correct value.
  # @param atn The ATN.
  #/
  def mark_precedence_decsisions(atn)
    atn.states.each { |state|
      next unless state.is_a? StarLoopEntryState
      # We analyze the ATN to determine if this ATN decision state is the
      # decision for the closure block that determines whether a
      # precedence rule should continue or complete.
      if atn.rule_to_start_state[state.rule_index].is_precedence_rule
        maybe_loop_end_state = state.transitions[-1].target
        if maybe_loop_end_state.is_a? LoopEndState and
           (maybe_loop_end_state.transitions[0].target.is_a? RuleStopState)
          state.is_precedence_decision = true
        end
      end
    }
  end

  def veirify_atn(atn)
    return unless deserialization_options.verify_atn
    # verify assumptions
    atn.states.each { |state|
      next if state.nil?
      check_condition((state.epsilon_only_transitions or state.transitions.size <= 1))
      if state.is_a? PlusBlockStartState
        check_condition((not state.loop_back_state.nil?))
      elsif state.is_a? StarLoopEntryState
        check_condition((not state.loop_back_state.nil?))
        check_condition(state.transitions.size == 2)
        if state.transitions[0].target.is_a? StarBlockStartState
          check_condition((state.transitions[1].target.is_a? LoopEndState))
          check_condition((not state.non_greedy))
        elsif state.transitions[0].target.is_a? LoopEndState
          check_condition((state.transitions[1].target.is_a? StarBlockStartState))
          check_condition(state.non_greedy)
        else
          raise(Exception, "IllegalState")
        end
      elsif state.is_a? StarLoopbackState
        check_condition(state.transitions.size == 1)
        check_condition((state.transitions[0].target.is_a? StarLoopEntryState))
      elsif state.is_a? LoopEndState
        check_condition((not state.loop_back_state.nil?))
      elsif state.is_a? RuleStartState
        check_condition((not state.stop_state.nil?))
      elsif state.is_a? BlockStartState
        check_condition((not state.end_state.nil?))
      elsif state.is_a? BlockEndState
        check_condition((not state.start_state.nil?))
      elsif state.is_a? DecisionState
        check_condition((state.transitions.size <= 1 or state.decision >= 0))
      else
        check_condition((state.transitions.size <= 1 or (state.is_a? RuleStopState)))
      end
    }
  end

  def check_condition(condition, message = nil)
    unless condition
      message = "IllegalState" if message.nil?
      raise(Exception, message)
    end
  end

  def read_int
    res = @data[@pos]
    @pos += 1
    res
  end

  def read_int_32
    low = read_int()
    high = read_int()
    (low | (high << 16))
  end

  # TODO:
  #def read_long
  #  low = read_int_32()
  #  high = read_int_32()
  #  ((low & 0x00000000FFFFFFFF) | (high << 32))
  #end

  def read_uuid
    bb = []
    7.downto(0) { |i|
      int = read_int()
      bb[(2 * i) + 1] = int & 0xFF
      bb[2 * i] = (int >> 8) & 0xFF
    }
    (byte_to_hex[bb[0]] + byte_to_hex[bb[1]] +
     byte_to_hex[bb[2]] + byte_to_hex[bb[3]] + "-" +
     byte_to_hex[bb[4]] + byte_to_hex[bb[5]] + "-" +
     byte_to_hex[bb[6]] + byte_to_hex[bb[7]] + "-" +
     byte_to_hex[bb[8]] + byte_to_hex[bb[9]] + "-" +
     byte_to_hex[bb[10]] + byte_to_hex[bb[11]] +
     byte_to_hex[bb[12]] + byte_to_hex[bb[13]] +
     byte_to_hex[bb[14]] + byte_to_hex[bb[15]])
  end

  def edge_factory(atn, type, src, trg, arg1, arg2, arg3, sets)
    target = atn.states[trg]
    return EpsilonTransition.new(target) if type == Transition::EPSILON
    return (arg3 != 0) ? RangeTransition.new(target, Token::EOF, arg2) : RangeTransition.new(target, arg1, arg2) if type == Transition::RANGE
    return RuleTransition.new(at.states[arg1], arg2, target) if type == Transition::RULE
    return PredicateTransition.new(target, arg1, arg2, (arg3 != 0)) if type == Transition::PREDICATE
    return PrecedencePredicateTransition.new(target, arg1) if type == Transition::PRECEDENCE
    return (arg3 != 0) ? AtomTransition.new(target, Token::EOF) : AtomTransition.new(target, arg1) if type == Transition::ATOM
    return ActionTranstion.new(target, arg1, arg2, (arg3 != 0)) if type == Transition::ACTION
    return SetTransition.new(target, sets[arg1]) if type == Transition::SET
    return NotSetTransition.new(targer, sets[arg1]) if type == Transition::NOT_SET
    return WildcardTransition.new(target) if type == Transition::WILDCARD
    raise(Exception, "The specified transition type: #{type} is not valid.")
  end

  def state_factory(type, rule_index)
    if @state_factories.nil?
      sf = [
        nil,
        lambda { BasicState.new },
        lambda { RuleStartState.new },
        lambda { BasicBlockStartState.new },
        lambda { PlusBlockStartState.new },
        lambda { StarBlockStartState.new },
        lambda { TokenStartState.new },
        lambda { RuleStopState.new },
        lambda { BlockEndState.new },
        lambda { StarLoopbackState.new },
        lambda { StarLoopEntryState.new },
        lambda { PlusLoopbackState.new },
        lambda { LoopEndState.new },
      ]
      @state_factories = sf
    end
    if type > @state_factories.size or @state_factories[type].nil?
      raise(Exception, "The specified transition type: #{type} is not valid.")
    else
      s = @state_factories[type].call
      unless s.nil?
        s.rule_index = rule_index
        return s
      end
    end
  end

  def lexer_action_factory(type, data1, data2)
    if @action_factories.nil?
      af = [
        lambda { |d1, d2| LexerChannelAction.new(d1) },
        lambda { |d1, d2| LexerCustomAction.new(d1, d2) },
        lambda { |d1, d2| LexerModeAction.new(d1) },
        lambda { |d1, d2| LexerMoreAction::INSTANCE },
        lambda { |d1, d2| LexerPopModeAction::INSTANCE },
        lambda { |d1, d2| LexerPushModeAction.new(d1) },
        lambda { |d1, d2| LexerSkipAction::INSTANCE },
        lambda { |d1, d2| LexerTypeAction.new(d1) },
      ]
      @action_factories = af
    end
    if type > @action_factories.size or @action_factories[type].nil?
      raise(Exception, "The specified transition type: #{type} is not valid.")
    else
      return @action_factories[type].call(data1, data2)
    end
  end
end

def create_byte_to_hex
  bth = []
  (0..255).each { |i|
    bth[i] = (i + 0x100).to_s[1..-1].upcase
  }
  bth
end

byte_to_hex = create_byte_to_hex()
