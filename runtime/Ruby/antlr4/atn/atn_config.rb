# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "atn_state"
require_relative "semantic_context"

require "ostruct"

class ATNConfig
  attr_accessor(:state, :alt, :context, :semantic_context,
                :reaches_into_outer_context, :precedence_filter_suppressed,
                :is_inside_set)

  # @param {Object} params A tuple: (ATN state, predicted alt, syntactic, semantic context). An OpenStruct object.
  # The syntactic context is a graph-structured stack node whose
  # path(s) to the root is the rule invocation(s)
  # chain used to arrive at the state.  The semantic context is
  # the tree of semantic predicates encountered before reaching
  # an ATN state
  #/
  def initialize(params, config)
    check_context(params, config)
    params = ATNConfig.check_params(params)
    config = ATNConfig.check_params(config, true)
    # The ATN state associated with this configuration///
    @state = params.state.nil? ? config.state : params.state
    # What alt (or lexer rule) is predicted by this configuration///
    @alt = params.alt.nil? ? config.alt : params.alt
    # The stack of invoking states leading to the rule/states associated
    # with this config.  We track only those contexts pushed during
    # execution of the ATN simulator
    @context = params.context.nil? ? config.context : params.context
    @semantic_context = params.semantic_context.nil? ?
      (config.semantic_context.nil? ? SemanticContext::NONE : config.semantic_context) : params.semantic_context
    # TODO: make it a boolean then
    # We cannot execute predicates dependent upon local context unless
    # we know for sure we are in the correct context. Because there is
    # no way to do this efficiently, we simply cannot evaluate
    # dependent predicates unless we are in the rule that initially
    # invokes the ATN simulator.
    # closure() tracks the depth of how far we dip into the
    # outer context: depth &gt; 0.  Note that it may not be totally
    # accurate depth since I don't ever decrement
    #/
    @reaches_into_outer_context = config.reaches_into_outer_context
    @precedence_filter_suppressed = config.reaches_into_outer_context
    @is_inside_set = false
  end

  def self.check_params(params, is_cfg = nil)
    if params.nil?
      result = OpenStruct.new(:state => nil, :alt => nil, :context => nil,
                              :semantic_context => nil)
      result.reaches_into_outer_context = 0 if is_cfg
      return result
    end
    props = OpenStruct.new
    props.state = params.state or nil
    props.alt = (params.alt.nil?) ? nil : params.alt
    props.context = params.context or nil
    props.semantic_context = params.semantic_context or nil
    if is_cfg
      props.reaches_into_outer_context = params.reaches_into_outer_context or 0
      props.precedence_filter_suppressed = params.precedence_filter_suppressed or false
    end
    props
  end

  def check_context(params, config)
    @context = nil if params.context.nil? and (config.nil? or config.context.nil?)
  end

  def hash
    unless @is_inside_set
      return [@state.state_number, @alt, @context, @semantic_context].hash
    end
    [@state.state_number, @alt, @semantic_context].hash
  end

  # An ATN configuration is equal to another if both have
  # the same state, they predict the same alternative, and
  # syntactic/semantic contexts are the same
  #/
  def eql?(other)
    unless @is_inside_set
      return true if self == other
      return false unless other.is_a? ATNConfig
      @state.state_number == other.state.state_number and
        @alt == other.alt and
        (@context.nil? ? other.context.nil? : @context.eql?(other.context)) and
        @semantic_context.eql?(other.semantic_context) and
        @precedence_filter_suppressed == other.precedence_filter_suppressed
    end
    return true if self == other
    return false unless other.is_a? ATNConfig
    @state.state_number == other.state.state_number and
    @alt == other.alt and
      @semantic_context.eql?(other.semantic_context)
  end

  def to_s
    "(#{@state},#{@alt}#{(@context.nil? ? "" : ",[#{@context.to_s}]")}#{(@semantic_context != SemanticContext::NONE ? ",#{@semantic_context.to_s}" : "")}#{(@reaches_into_outer_context > 0 ? ",up=#{@reaches_into_outer_context}" : "")})"
  end
end

class LexerATNConfig < ATNConfig
  attr_accessor(:lexer_action_executor, :passed_through_non_greedy_decision)

  def initialize(params, config)
    super(params, config)
    # This is the backing field for {@link //getLexerActionExecutor}.
    lexer_action_executor = params.lexer_action_executor or nil
    @lexer_action_executor = lexer_action_executor or (config.nil? ? nil : config.lexer_action_executor)
    @passed_through_non_greedy_decision = config.nil? ? false : check_non_greedy_decision(config, @state)
  end

  def hash
    [@state.state_number, @alt, @context, @semantic_context].hash
  end

  def eql?(other)
    unless @is_inside_set
      return (self == other or (other.is_a? LexerATNConfig and
                                @passed_through_non_greedy_decision == other.passed_through_non_greedy_decision and
                                (@lexer_action_executor ? @lexer_action_executor.eql?(other.lexer_action_executor) : (not other.lexer_action_executor)) and
                                super(other)))
    end
    return true if self == other
    return false unless other.is_a? ATNConfig
    @state.state_number == other.state.state_number and
      @alt == other.alt and
      (@context.nil? ? other.context.nil? : @context.eql?(other.context)) and
      @semantic_context.eql?(other.semantic_context) and
      @precedence_filter_suppressed == other.precedence_filter_suppressed
  end

  def check_non_greedy_decision(source, target)
    source.passed_through_non_greedy_decision or (target.is_a? DecisionState) and target.non_greedy
  end
end
