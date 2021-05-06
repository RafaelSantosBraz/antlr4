# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require "set"

#
# A tree structure used to record the semantic context in which
# an ATN configuration is valid.  It's either a single predicate,
# a conjunction {@code p1&&p2}, or a sum of products {@code p1||p2}.
#
# <p>I have scoped the {@link AND}, {@link OR}, and {@link Predicate} subclasses of
# {@link SemanticContext} within the scope of this outer class.</p>
#/
class SemanticContext

  # For context independent predicates, we evaluate them without a local
  # context (i.e., null context). That way, we can evaluate them without
  # having to create proper rule-specific context during prediction (as
  # opposed to the parser, which creates them naturally). In a practical
  # sense, this avoids a cast exception from RuleContext to myruleContext.
  #
  # <p>For context dependent predicates, we must pass in a local context so that
  # references such as $arg evaluate properly as _localctx.arg. We only
  # capture context dependent predicates in the context in which we begin
  # prediction, so we passed in the outer context here in case of context
  # dependent predicate evaluation.</p>
  #/
  def evaluate(parser, outer_context)
  end

  # Evaluate the precedence predicates for the context and reduce the result.
  #
  # @param parser The parser instance.
  # @param outerContext The current parser context object.
  # @return The simplified semantic context after precedence predicates are
  # evaluated, which will be one of the following values.
  # <ul>
  # <li>{@link //NONE}: if the predicate simplifies to {@code true} after
  # precedence predicates are evaluated.</li>
  # <li>{@code null}: if the predicate simplifies to {@code false} after
  # precedence predicates are evaluated.</li>
  # <li>{@code this}: if the semantic context is not changed as a result of
  # precedence predicate evaluation.</li>
  # <li>A non-{@code null} {@link SemanticContext}: the new simplified
  # semantic context after precedence predicates are evaluated.</li>
  # </ul>
  #/

  def eval_precedence(parser, outer_context)
    self
  end

  def self.and_context(a, b)
    return b if a.nil? or a == SemanticContext::NONE
    return a if b.nil? or b == SemanticContext::NONE
    result = AND.new(a, b)
    return result.opnds[0] if result.opnds.size == 1
    result
  end

  def self.or_context(a, b)
    return b if a.nil?
    return a if b.nil?
    return SemanticContext::NONE if a == SemanticContext::NONE or b == SemanticContext::NONE
    result = OR.new(a, b)
    return result.opnds[0] if result.opnds.size == 1
    result
  end
end

class Predicate < SemanticContext
  attr_accessor(:rule_index, :pred_index, :is_ctx_dependent)

  def initialize(rule_index = -1, pred_index = -1, is_ctx_dependent = false)
    @rule_index = rule_index
    @pred_index = pred_index
    @is_ctx_dependent = is_ctx_dependent
  end

  def evaluate(parser, outer_context)
    local_ctx = @is_ctx_dependent ? outer_context : nil
    parser.sempred(local_ctx, @rule_index, @pred_index)
  end

  def hash
    [@rule_index, @pred_index, @is_ctx_dependent].hash
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? Predicate
    @rule_index == other.rule_index and
      @pred_index == other.pred_index and
      @is_ctx_dependent == other.is_ctx_dependent
  end

  def to_s
    "{#{@rule_index}:#{@pred_index}}"
  end
end

# The default {@link SemanticContext}, which is semantically equivalent to
# a predicate of the form {@code {true}?}
#/
SemanticContext::NONE = Predicate.new

class PrecedencePredicate < SemanticContext
  attr_accessor(:precedence)

  def initialize(precedence = 0)
    @precedence = precedence
  end

  def evaluate(parser, outer_context)
    parser.precpred(outer_context, @precedence)
  end

  def eval_precedence(parser, outer_context)
    return SemanticContext::NONE if parser.precpred(outer_context, @precedence)
    nil
  end

  def compare_to(other)
    @precedence - other.precedence
  end

  def hash
    @precedence.hash
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? PrecedencePredicate
    @precedence == other.precedence
  end

  def to_s
    "{#{@precedence}}"
  end

  def self.filter_precedence_predicates(set)
    set.select { |context| context.is_a? PrecedencePredicate }
  end
end

class AND < SemanticContext
  attr_accessor(:opnds)

  # A semantic context which is true whenever none of the contained contexts
  # is false
  #/
  def initialize(a, b)
    operands = Set[]
    if a.is_a? AND
      a.opnds.each { |o| operands << o }
    else
      operands << a
    end
    if b.is_a? AND
      b.opnds.each { |o| operands << o }
    else
      operands << b
    end
    precedente_predicates = PrecedencePredicate.filter_precedence_predicates(operands)
    if precedente_predicates.size > 0
      # interested in the transition with the lowest precedence
      reduced = nil
      precedente_predicates.each { |p|
        reduced = p if reduced.nil? or p.precedence < reduced.precedente
      }
      operands << reduced
    end
    @opnds = operands.to_a
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? AND
    @opnds == other.opnds
  end

  def hash
    [@opnds, "AND"].hash
  end

  # {@inheritDoc}
  #
  # <p>
  # The evaluation of predicates by this context is short-circuiting, but
  # unordered.</p>
  #/
  def evaluate(parser, outer_context)
    @opnds.none? { |op| not op.evaluate(parser, outer_context) }
  end

  def eval_precedence(parser, outer_context)
    differs = false
    operands = []
    @opnds.each { |context|
      evaluated = context.eval_precedence(parser, outer_context)
      differs |= (evaluated != context)
      # The AND context is false if any element is false
      return nil if evaluated.nil?
      # Reduce the result by skipping true elements
      operands << evaluated if evaluated != SemanticContext::NONE
    }
    return self unless differs
    # all elements were true, so the AND context is true
    return SemanticContext::NONE if operands.size == 0
    operands.reduce { |result, o|
      result.nil? ? o : SemanticContext.and_context(result, o)
    }
  end

  def to_s
    s = @opnds.map(&:to_s)
    (s.size > 3 ? s[3..-1] : s).join("&&")
  end
end

class OR < SemanticContext
  attr_accessor(:opnds)

  # A semantic context which is true whenever at least one of the contained
  # contexts is true
  #/
  def initialize(a, b)
    operands = Set[]
    if a.is_a? OR
      a.opnds.each { |o| operands << o }
    else
      operands << a
    end
    if b.is_a? OR
      b.opnds.each { |o| operands << o }
    else
      operands << b
    end
    precedente_predicates = PrecedencePredicate.filter_precedence_predicates(operands)
    if precedente_predicates.size > 0
      # interested in the transition with the lowest precedence
      s = precedente_predicates.sort { |aa, bb| a.compare_to(b) }
      reduced = s[-1]
      operands << reduced
    end
    @opnds = operands.to_a
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? OR
    @opnds == other.opnds
  end

  def hash
    [@opnds, "OR"].hash
  end

  # {@inheritDoc}
  #
  # <p>
  # The evaluation of predicates by this context is short-circuiting, but
  # unordered.</p>
  #/
  def evaluate(parser, outer_context)
    @opnds.any? { |op| op.evaluate(parser, outer_context) }
  end

  def eval_precedence(parser, outer_context)
    differs = false
    operands = []
    @opnds.each { |context|
      evaluated = context.eval_precedence(parser, outer_context)
      differs |= (evaluated != context)
      # The OR context is false if any element is true
      return SemanticContext::NONE if evaluated == SemanticContext::NONE
      # Reduce the result by skipping false elements
      operands << evaluated if evaluated != nil
    }
    return self unless differs
    # all elements were true, so the AND context is true
    return nil if operands.size == 0
    result = nil
    operands.each { |o|
      result.nil? ? o : SemanticContext.or_context(result, o)
    }
    result
  end

  def to_s
    s = @opnds.map(&:to_s)
    (s.size > 3 ? s[3..-1] : s).join("||")
  end
end
