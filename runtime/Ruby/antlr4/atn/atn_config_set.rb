# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "atn"
require_relative "semantic_context"
require_relative "../prediction_context"
require_relative "../utils"

# Specialized {@link Set}{@code <}{@link ATNConfig}{@code >} that can track
# info about the set, with support for combining similar configurations using a
# graph-structured stack
#/
class ATNConfigSet
  attr_accessor(:config_lookup, :full_ctx, :read_only, :configs, :unique_alt,
                :conflicting_alts, :has_semantic_context, :dips_into_outer_context,
                :cached_hash_code)

  def initialize(full_ctx = true)
    @config_lookup = CustomSetForATNConfigSet.new
    # Indicates that this configuration set is part of a full context
    # LL prediction. It will be used to determine how to merge $. With SLL
    # it's a wildcard whereas it is not for LL context merge
    #/
    @full_ctx = full_ctx
    # Indicates that the set of configurations is read-only. Do not
    # allow any code to manipulate the set; DFA states will point at
    # the sets and they must not change. This does not protect the other
    # fields; in particular, conflictingAlts is set after
    # we've made this readonly
    #/
    @read_only = false
    # Track the elements as they are added to the set
    @configs = []
    # TODO: these fields make me pretty uncomfortable but nice to pack up info
    # together, saves recomputation
    # TODO: can we track conflicts as they are added to save scanning configs
    # later?
    @unique_alt = 0
    @conflicting_alts = nil
    # Used in parser and lexer. In lexer, it indicates we hit a pred
    # while computing a closure operation. Don't make a DFA state from this
    #/
    @has_semantic_context = false
    @dips_into_outer_context = false
    @cached_hash_code = -1
  end

  # Adding a new config means merging contexts with existing configs for
  # {@code (s, i, pi, _)}, where {@code s} is the
  # {@link ATNConfig//state}, {@code i} is the {@link ATNConfig//alt}, and
  # {@code pi} is the {@link ATNConfig//semanticContext}. We use
  # {@code (s,i,pi)} as key.
  #
  # <p>This method updates {@link //dipsIntoOuterContext} and
  # {@link //hasSemanticContext} when necessary.</p>
  #/
  def add(config, merge_cache = nil)
    raise(Exception, "This set is readonly") if @read_only
    @has_semantic_context = true if config.semantic_context != SemanticContext::NONE
    @dips_into_outer_context = true if config.reaches_into_outer_context > 0
    if @config_lookup.is_a? CustomSetForATNConfigSet
      if @config_lookup.include? config
        existing = @config_lookup.find_eql(config)
      else
        @config_lookup.add(config)
        existing = config
      end
    else
      if @config_lookup.include? config
        existing = @config_lookup.find { |v| v.eql? config }
      else
        @config_lookup.add(config)
        existing = config
      end
    end
    if existing == config
      @cached_hash_code = -1
      @configs << config #track order here
    end
    # a previous (s,i,pi,_), merge with it and save result
    root_is_wildcard = (not @full_ctx)
    merged = merge(existing.context, config.context, root_is_wildcard, merge_cache)
    # no need to check for existing.context, config.context in cache
    # since only way to create new graphs is "call rule" and here. We
    # cache at both places
    #/
    existing.reaches_into_outer_context = [existing.reaches_into_outer_context,
                                           config.reaches_into_outer_context].max
    # make sure to preserve the precedence filter suppression during the merge
    existing.precedence_filter_suppressed = true if config.precedence_filter_suppressed
    existing.context = merged       # replace context; no need to alt mapping
    return true
  end

  def get_states
    @configs.map { |conf| conf.state }.to_set
  end

  def get_predicates
    preds = []
    @configs.each { |conf|
      c = conf.semantic_context
      preds << c.semantic_context if c != SemanticContext::NONE
    }
    preds
  end

  def optimize_configs(interpreter)
    raise(Exception, "This set is readonly") if @read_only
    return if @config_lookup.size == 0
    @configs.each { |conf|
      conf.context = interpreter.get_cached_context(conf.context)
    }
  end

  def add_all(coll)
    coll.each { |c| add(c) }
    false
  end

  def eql?(other)
    self == other or
    (other.is_a? ATNConfigSet and
     @configs == other.configs and
     @full_ctx == other.full_ctx and
     @unique_alt == other.unique_alt and
     @conflicting_alts == other.conflicting_alts and
     @has_semantic_context == other.has_semantic_context and
     @dips_into_outer_context == other.dips_into_outer_context)
  end

  def hash
    if @cached_hash_code == -1
      @cached_hash_code = @configs.hash
    end
    @cached_hash_code
  end

  def empty?
    @configs.empty?
  end

  def contains?(item)
    raise(Exception, "This method is not implemented for readonly sets.") if @config_lookup.nil?
    @config_lookup.include? item
  end

  def clear
    raise(Exception, "This set is readonly") if @read_only
    @configs = []
    @cached_hash_code = -1
    @config_lookup = CustomSetForATNConfigSet.new
  end

  def set_read_only(read_only)
    @read_only = read_only
    if read_only
      @config_lookup = nil
    end
  end

  def to_s
    "#{@configs}#{@has_semantic_context ? ",has_semantic_context=#{@has_semantic_context}" : ""}#{@unique_alt != ATN.INVALID_ALT_NUMBER ? ",unique_alt=#{@unique_alt}" : ""}#{@conflicting_alts != nil ? "conflicting_alts=#{@conflicting_alts}" : ""}#{@dips_into_outer_context ? ",dips_into_outer_context" : ""}"
  end

  def items
    @configs
  end

  def size
    @configs.size
  end
end

class OrderedATNConfigSet < ATNConfigSet
  def initialize
    @config_lookup = Set[]
  end
end
