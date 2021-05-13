# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "../token"
require_relative "../lexer"
require_relative "atn"
require_relative "atn_simulator"
require_relative "../dfa/dfa_state"
require_relative "atn_config_set"
require_relative "../prediction_context"
require_relative "atn_state"
require_relative "atn_config"
require_relative "transition"
require_relative "lexer_action_executor"
require_relative "../error/errors"
require_relative "../utils"

require "ostruct"

class SimState
  attr_accessor(:index, :line, :column, :dfa_state)

  def initialize
    SimState.reset_sim_state(self)
  end

  def reset
    SimState.reset_sim_state(self)
  end

  def self.reset_sim_state(sim)
    sim.index = -1
    sim.line = 0
    sim.column = -1
    sim.dfa_state = nil
  end
end

class LexerATNSimulator < ATNSimulator
  @@debug = false
  @@dfa_debug = false
  MIN_DFA_EDGE = 0
  MAX_DFA_EDGE = 127;  # forces unicode to stay in ATN
  @@match_calls = 0

  def self.debug
    @@debug
  end

  def self.debug=(debug)
    @@debug = debug
  end

  def self.dfa_debug
    @@dfa_debug
  end

  def self.dfa_debug=(dfa_debug)
    @@dfa_debug = dfa_debug
  end

  def self.match_calls
    @@match_calls
  end

  def self.match_calls(match_calls)
    @@match_calls = match_calls
  end

  attr_accessor(:decisio_to_dfa, :recog, :start_index, :line, :column,
                :mode, :prev_accept, :match_calls, :output)
  # When we hit an accept state in either the DFA or the ATN, we
  # have to notify the character stream to start buffering characters
  # via {@link IntStream//mark} and record the current state. The current sim state
  # includes the current index into the input, the current line,
  # and current character position in that line. Note that the Lexer is
  # tracking the starting line and characterization of the token. These
  # variables track the "state" of the simulator when it hits an accept state.
  #
  # <p>We track these variables separately for the DFA and ATN simulation
  # because the DFA simulation often has to fail over to the ATN
  # simulation. If the ATN simulation fails, we need the DFA to fall
  # back to its previously accepted state, if any. If the ATN succeeds,
  # then the ATN does the accept and the DFA simulator that invoked it
  # can simply return the predicted token type.</p>
  #/
  def initialize(recog, atn, decision_to_dfa, shared_context_cache_,
                 output = STDOUT)
    super(atn, shared_context_cache_)
    @decision_to_dfa = decision_to_dfa
    @recog = recog
    # The current token's starting index into the character stream.
    # Shared across DFA to ATN simulation in case the ATN fails and the
    # DFA did not have a previous accept state. In this case, we use the
    # ATN-generated exception object
    #/
    @start_index = -1
    # line number 1..n within the input///
    @line = 1
    # The index of the character relative to the beginning of the line
    # 0..n-1
    #/
    @column = 0
    @mode = Lexer::DEFAULT_MODE
    # Used during DFA/ATN exec to record the most recent accept configuration
    # info
    @prev_accept = SimState.new
    @output = output
  end

  def copy_state(simulator)
    @column = simulator.column
    @line = simulator.line
    @mode = simulator.mode
    @start_index = simulator.start_index
  end

  def match(input, mode_)
    @match_calls += 1
    @mode = mode_
    mark = input.mark()
    begin
      @start_index = input.index
      @prev_accept.reset()
      dfa = @decision_to_dfa[mode]
      return match_atn(input) if dfa.s0.nil?
      return exec_atn(input, dfa.s0)
    ensure
      input.release(mark)
    end
  end

  def reset
    @prev_accept.reset()
    @start_index = -1
    @line = 1
    @column = 0
    @mode = Lexer::DEFAULT_MODE
  end

  def match_atn(input)
    start_state = @atn.mode_to_start_state[@mode]
    @output.puts "match_atn mode #{@mode} start: #{start_state}" if LexerATNSimulator.debug
    old_mode = @mode
    s0_closure = compute_start_state(inout, start_state)
    suppress_edge = s0_closure.has_semantic_context
    s0_closure.has_semantic_context = false
    nextt = add_dfa_state(s0_closure)
    @decision_to_dfa[@mode].s0 = nextt unless suppress_edge
    predict = exec_atn(input, nextt)
    @output.puts "DFA after match_atn: #{@decision_to_dfa[old_mode].to_lexer_string}" if LexerATNSimulator.debug
    predict
  end

  def exec_atn(input, ds0)
    @output.puts "start state closure=#{ds0.configs}" if LexerATNSimulator.debug
    if ds0.is_accept_state
      # allow zero-length tokens
      capture_sim_state(@prev_accept, input, ds0)
    end
    t = input.la(1)
    s = ds0 # s is current/from DFA state
    while true # while more work
      @output.puts "exec_atn loop starting closure: #{s.configs}" if LexerATNSimulator.debug
      # As we move src->trg, src->trg, we keep track of the previous trg to
      # avoid looking up the DFA state again, which is expensive.
      # If the previous target was already part of the DFA, we might
      # be able to avoid doing a reach operation upon t. If s!=null,
      # it means that semantic predicates didn't prevent us from
      # creating a DFA state. Once we know s!=null, we check to see if
      # the DFA state has an edge already for t. If so, we can just reuse
      # it's configuration set; there's no point in re-computing it.
      # This is kind of like doing DFA simulation within the ATN
      # simulation because DFA simulation is really just a way to avoid
      # computing reach/closure sets. Technically, once we know that
      # we have a previously added DFA state, we could jump over to
      # the DFA simulator. But, that would mean popping back and forth
      # a lot and making things more complicated algorithmically.
      # This optimization makes a lot of sense for loops within DFA.
      # A character will take us back to an existing DFA state
      # that already has lots of edges out of it. e.g., .* in comments.
      # print("Target for:" + str(s) + " and:" + str(t))
      #/
      target = get_existing_target_state(s, t)
      # print("Existing:" + str(target))
      if target.nil?
        target = compute_target_state(input, s, t)
        # print("Computed:" + str(target))
      end
      break if target == ATNSimulator::ERROR
      # If this is a consumable input element, make sure to consume before
      # capturing the accept state so the input index, line, and char
      # position accurately reflect the state of the interpreter at the
      # end of the token.
      consume(input) if t != Token::EOF
      if target.is_accept_state
        capture_sim_state(@prev_accept, input, target)
        break if t == Token::EOF
      end
      t = input.la(1)
      s = target # flip; current DFA target becomes new src/from state
    end
    fail_or_accept(@prev_accept, input, s.configs, t)
  end

  # Get an existing target state for an edge in the DFA. If the target state
  # for the edge has not yet been computed or is otherwise not available,
  # this method returns {@code null}.
  #
  # @param s The current DFA state
  # @param t The next input symbol
  # @return The existing target DFA state for the given input symbol
  # {@code t}, or {@code null} if the target state for this edge is not
  # already cached
  #/
  def get_existing_target_state(s, t)
    return nil if s.edges.nil? or t < LexerATNSimulator::MIN_DFA_EDGE or
                  t > LexerATNSimulator::MAX_DFA_EDGE
    target = s.edges[t - LexerATNSimulator::MIN_DFA_EDGE]
    if LexerATNSimulator.debug and not target.nil?
      @output.puts "reuse state #{s.state_number} edge to #{target.state_number}"
    end
    target
  end

  # Compute a target state for an edge in the DFA, and attempt to add the
  # computed state and corresponding edge to the DFA.
  #
  # @param input The input stream
  # @param s The current DFA state
  # @param t The next input symbol
  #
  # @return The computed target DFA state for the given input symbol
  # {@code t}. If {@code t} does not lead to a valid DFA state, this method
  # returns {@link //ERROR}.
  #/
  def compute_target_state(input, s, t)
    reach = OrderedATNConfigSet.new
    # if we don't find an existing DFA state
    # Fill reach starting from closure, following t transitions
    get_reachable_config_set(input, s.configs, reach, t)
    if reach.items.size == 0 # we got nowhere on t from s
      unless reach.has_semantic_context
        # we got nowhere on t, don't throw out this knowledge; it'd
        # cause a failover from DFA later.
        add_dfa_edge(s, t, ATNSimulator::ERROR)
      end
      return ATNSimulator::ERROR
    end
    # Add an edge from s to target DFA found/created for reach
    add_dfa_edge(s, t, nil, reach)
  end

  def fail_or_accept(prev_accept, input, reach, t)
    if not @prev_accept.dfa_state.nil?
      lexer_action_executor = prev_accept.dfa_state.lexer_action_executor
      accept(input, lexer_action_executor, @start_index)
      return prev_accept.dfa_state.prediction
    else
      # if no accept and EOF is first char, return EOF
      return Token::EOF if t == Token::EOF and input.index == @start_index
      raise(LexerNoViableAltException.new(@recog, input, @start_index, reach))
    end
  end

  # Given a starting configuration set, figure out all ATN configurations
  # we can reach upon input {@code t}. Parameter {@code reach} is a return
  # parameter.
  #/
  def get_reachable_config_set(input, closure, reach, t)
    # this is used to skip processing for configs which have a lower priority
    # than a config that already reached an accept state for the same rule
    skip_alt = ATN::INVALID_ALT_NUMBER
    closure.items.each { |cfg|
      current_alt_reached_accept_state = (cfg.alt == skip_alt)
      next if current_alt_reached_accept_state and
              cfg.passed_through_non_greedy_decision
      if LexerATNSimulator.debug
        @output.puts "testing #{get_token_name(t)} at #{cfg.to_s}"
      end
      cfg.state.transitions.each { |trans|
        target = get_reachable_target(trans, t)
        unless target.nil?
          lexer_action_executor = cfg.lexer_action_executor
          unless lexer_action_executor.nil?
            lexer_action_executor =
              lexer_action_executor.fix_offset_before_match(input.index -
                                                            @start_index)
          end
          treat_eof_as_epsilon = (t == Token::EOF)
          config = LexerATNConfig.new(OpenStruct.new(
            :state => target, :lexer_action_executor => lexer_action_executor,
          ), cfg)
          if closure(
            input, config, reach, current_alt_reached_accept_state, true,
            treat_eof_as_epsilon
          )
            # any remaining configs for this alt have a lower priority
            # than the one that just reached an accept state.
            skip_alt = cfg.alt
          end
        end
      }
    }
  end

  def accept(input, lexer_action_executor, start_index, index, line, char_pos)
    @output.puts "ACTION #{lexer_action_executor}" if LexerATNSimulator.debug
    # seek to after last char in token
    input.seek(index)
    @line = line
    @column = char_pos
    if not lexer_action_executor.nil and not @recog.nil?
      lexer_action_executor.execute(@recog, input, start_index)
    end
  end

  def get_reachable_target(trans, t)
    return trans.matches(t, 0, Lexer::MAX_CHAR_VALUE)
    nil
  end

  def compute_start_state(input, p)
    initial_context = PredictionContext::EMPTY
    configs = OrderedATNConfigSet.new
    p.transitions.map { |trans| trans.target }.each_with_index { |target, i|
      cfg = LexerATNConfig.new(OpenStruct.new(
        :state => target, :alt => i + 1, :context => initial_context,
      ), nil)
      closure(input, cfg, configs, false, false, false)
    }
    configs
  end

  # Since the alternatives within any lexer decision are ordered by
  # preference, this method stops pursuing the closure as soon as an accept
  # state is reached. After the first accept state is reached by depth-first
  # search from {@code config}, all other (potentially reachable) states for
  # this rule would have a lower priority.
  #
  # @return {Boolean} {@code true} if an accept state is reached, otherwise
  # {@code false}.
  #/
  def closure(input, config, configs, current_alt_reached_accept_state,
              speculative, treat_eof_as_epsilon)
    cfg = nil
    @output.puts "closure(#{config.to_s})" if LexerATNSimulator.debug
    if config.state.is_a? RuleStopState
      if LexerATNSimulator.debug
        if not @recog.nil?
          @output.puts "closure at #{@recog.rule_names[config.state.rule_index]} rule stop #{config}"
        else
          @output.puts "closure at rule stop #{config}"
        end
      end
      if config.context.nil? or config.context.has_empty_path()
        if config.context.nil? or config.context.is_empty()
          configs.add(config)
        else
          configs.add(LexerATNConfig.new(OpenStruct.new(
            :state => config.state, :context => PredicitionContext::EMPTY,
          )), config)
        end
      end
      if not config.context.nil? and not config.context.is_empty()
        (0..(config.context.size - 1)).each { |i|
          if config.context.get_return_state(i) != PredictionContext::EMPTY_RETURN_STATE
            new_context = config.context.get_parent(i) # "pop" return state
            return_state = @atn.states[config.context.get_return_state(i)]
            cfg = LexerATNConfig.new(OpenStruct.new(
              :state => return_state, :context => new_context,
            ), config)
            current_alt_reached_accept_state = closure(
              input, cfg, configs, current_alt_reached_accept_state,
              speculative, treat_eof_as_epsilon
            )
          end
        }
      end
      return current_alt_reached_accept_state
    end
    # optimization
    unless config.state.epsilon_only_transitions
      if not current_alt_reached_accept_state or
         not config.passed_through_non_greedy_decision
        configs.add(config)
      end
    end
    config.state.transitions.each { |trans|
      cfg = get_epsilon_target(
        input, config, trans, configs, speculative, treat_eof_as_epsilon
      )
      unless cfg.nil?
        current_alt_reached_accept_state = closure(
          input, cfg, configs, current_alt_reached_accept_state,
          speculative, treat_eof_as_epsilon
        )
      end
    }
    current_alt_reached_accept_state
  end

  # side-effect: can alter configs.hasSemanticContext
  def get_epsilon_target(input, config, trans, configs, speculative,
                         treat_eof_as_epsilon)
    cfg = nil
    if trans.serialization_type == Transition::RULE
      new_context = SingletonPredictionContext.create(
        config.context,
        trans.follow_state.state_number
      )
      cfg = LexerATNConfig.new(OpenStruct.new(
        :state => trans.target, :context => new_context,
      ), config)
    elsif trans.serialization_type == Transition::PRECEDENCE
      raise(Exception, "Precedence predicates are not supported in lexers.")
    elsif trans.serialization_type == Transition::PREDICATE
      # Track traversing semantic predicates. If we traverse,
      # we cannot add a DFA state for this "reach" computation
      # because the DFA would not test the predicate again in the
      # future. Rather than creating collections of semantic predicates
      # like v3 and testing them on prediction, v4 will test them on the
      # fly all the time using the ATN not the DFA. This is slower but
      # semantically it's not used that often. One of the key elements to
      # this predicate mechanism is not adding DFA states that see
      # predicates immediately afterwards in the ATN. For example,

      # a : ID {p1}? | ID {p2}? ;

      # should create the start state for rule 'a' (to save start state
      # competition), but should not create target of ID state. The
      # collection of ATN states the following ID references includes
      # states reached by traversing predicates. Since this is when we
      # test them, we cannot cash the DFA state target of ID.
      if LexerATNSimulator.debug
        @output.puts "EVAL rule #{trans.rule_index}:#{trans.pred_index}"
      end
      configs.has_semantic_context = true
      if evaluate_predicate(input, trans.rule_index, trans.pred_index, speculative)
        cfg = LexerATNConfig.new(OpenStruct.new(:state => trans.target), config)
      end
    elsif trans.serialization_type == Transition::ACTION
      if config.context.nil? or config.context.has_empty_path()
        # execute actions anywhere in the start rule for a token.
        #
        # TODO: if the entry rule is invoked recursively, some
        # actions may be executed during the recursive call. The
        # problem can appear when hasEmptyPath() is true but
        # isEmpty() is false. In this case, the config needs to be
        # split into two contexts - one with just the empty path
        # and another with everything but the empty path.
        # Unfortunately, the current algorithm does not allow
        # getEpsilonTarget to return two configurations, so
        # additional modifications are needed before we can support
        # the split operation.
        lexer_action_executor = LexerActionExecutor.append(
          config.lexer_action_executor,
          @atn.lexer_actions[trans.action_index]
        )
        cfg = LexerATNConfig.new(OpenStruct.new(
          :state => trans.target,
          :lexer_action_executor => lexer_action_executor,
        ), config)
      else
        # ignore actions in referenced rules
        cfg = LexerATNConfig.new(OpenStruct.new(:state => trans.target), config)
      end
    elsif trans.serialization_type == Transition::EPSILON
      cfg = LexerATNConfig.new(OpenStruct.new(:state => trans.target), confi)
    elsif trans.serialization_type == Transition::ATOM or
          trans.serialization_type == Transition::RANGE or
          trans.serialization_type == Transition::SET
      if treat_eof_as_epsilon
        if trans.matches(Token::EOF, 0, Lexer::MAX_CHAR_VALUE)
          cfg = LexerATNConfig.new(OpenStruct.new(:state => trans.target), config)
        end
      end
    end
    cfg
  end

  # Evaluate a predicate specified in the lexer.
  #
  # <p>If {@code speculative} is {@code true}, this method was called before
  # {@link //consume} for the matched character. This method should call
  # {@link //consume} before evaluating the predicate to ensure position
  # sensitive values, including {@link Lexer//getText}, {@link Lexer//getLine},
  # and {@link Lexer//getcolumn}, properly reflect the current
  # lexer state. This method should restore {@code input} and the simulator
  # to the original state before returning (i.e. undo the actions made by the
  # call to {@link //consume}.</p>
  #
  # @param input The input stream.
  # @param ruleIndex The rule containing the predicate.
  # @param predIndex The index of the predicate within the rule.
  # @param speculative {@code true} if the current index in {@code input} is
  # one character before the predicate's location.
  #
  # @return {@code true} if the specified predicate evaluates to
  # {@code true}.
  #/
  def evaluate_predicate(input, rule_index, pred_index, speculative)
    # assume true if no recognizer was provided
    return true if @recog.nil?
    return @recog.sempred(nil, rule_index, pred_index) unless speculative
    saved_column = @column
    saved_line = @line
    index = input.index
    marker = input.mark()
    begin
      consume(input)
      return @recog.sempred(nil, rule_index, pred_index)
    ensure
      @column = saved_column
      @line = saved_line
      input.seek(index)
      input.release(marker)
    end
  end

  def capture_sim_state(settings, input, dfa_state)
    settings.index = input.index
    settings.line = @line
    settings.column = @column
    settings.dfa_state = dfa_state
  end

  def add_dfa_edge(from_, tk, to = nil, cfgs = nil)
    if to.nil? and not cfgs.nil?
      # leading to this call, ATNConfigSet.hasSemanticContext is used as a
      # marker indicating dynamic predicate evaluation makes this edge
      # dependent on the specific input sequence, so the static edge in the
      # DFA should be omitted. The target DFAState is still created since
      # execATN has the ability to resynchronize with the DFA state cache
      # following the predicate evaluation step.
      #
      # TJP notes: next time through the DFA, we see a pred again and eval.
      # If that gets us to a previously created (but dangling) DFA
      # state, we can continue in pure DFA mode from there.
      # /
      suppress_edge = cfgs.has_semantic_context
      cfgs.has_semantic_context = false
      to = add_dfa_state(cfgs)
      return to if suppress_edge
    end
    # add the edge
    return to if tk < LexerATNSimulator::MIN_DFA_EDGE or
                 tk > LexerATNSimulator::MAX_DFA_EDGE
    @output.puts "EDGE #{from_} -> #{to} upon #{tk}" if LexerATNSimulator.debug
    # make room for tokens 1..n and -1 masquerading as index 0
    from_.edges = [] if from_.edges.nil?
    from_.edges[tk - LexerATNSimulator::MIN_DFA_EDGE] = to # connect
    to
  end

  # Add a new DFA state if there isn't one with this set of
  # configurations already. This method also detects the first
  # configuration containing an ATN rule stop state. Later, when
  # traversing the DFA, we will know which rule to accept.
  #/
  def add_dfa_state(configs)
    proposed = DFAState.new(nil, configs)
    first_config_with_rule_stop_state = nil
    configs.items.each { |cfg|
      if cfg.state.is_a? RuleStopState
        first_config_with_rule_stop_state = cfg
        break
      end
    }
    unless first_config_with_rule_stop_state.nil?
      proposed.is_accept_state = true
      proposed.lexer_action_executor =
        first_config_with_rule_stop_state.lexer_action_executor
      proposed.prediction = @atn.rule_to_token_type[
        first_config_with_rule_stop_state.state.rule_index
      ]
    end
    dfa = @decision_to_dfa[@mode]
    existing = dfa.states.get(proposed)
    return existing unless existing.nil?
    new_state = proposed
    new_state.state_number = dfa.states.size
    configs.set_read_only(true)
    new_state.configs = configs
    dfa.states.add(new_state)
    new_state
  end

  def get_dfa(mode)
    @decision_to_dfa[mode]
  end

  # Get the text matched so far for the current token.
  def get_text(input)
    # index is first lookahead char, don't include.
    input.get_text(@start_index, input.index - 1)
  end

  def consume(input)
    cur_char = input.la(1)
    if cur_char == "\n".ord
      @line += 1
      @column = 0
    else
      @column += 1
    end
    input.consume()
  end

  def get_token_name(tt)
    return "EOF" if tt == -1
    "'#{10.chr(DECODE_ENCODING)}'"
  end
end
