# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require_relative "../dfa/dfa_state"
require_relative "atn_config_set"
require_relative "../prediction_context"
require_relative "../utils"

class ATNSimulator

  # Must distinguish between missing edge and edge we know leads nowhere///
  ERROR = DFAState.new(0x7FFFFFFF, ATNConfigSet.new)

  attr_accessor(:atn, :shared_context_cache)

  def initialize(atn, shared_context_cache)
    # The context cache maps all PredictionContext objects that are ==
    # to a single cached copy. This cache is shared across all contexts
    # in all ATNConfigs in all DFA states.  We rebuild each ATNConfigSet
    # to use only cached nodes/graphs in addDFAState(). We don't want to
    # fill this during closure() since there are lots of contexts that
    # pop up but are not used ever again. It also greatly slows down closure().
    #
    # <p>This cache makes a huge difference in memory and a little bit in speed.
    # For the Java grammar on java.*, it dropped the memory requirements
    # at the end from 25M to 16M. We don't store any of the full context
    # graphs in the DFA because they are limited to local context only,
    # but apparently there's a lot of repetition there as well. We optimize
    # the config contexts before storing the config set in the DFA states
    # by literally rebuilding them with cached subgraphs only.</p>
    #
    # <p>I tried a cache for use during closure operations, that was
    # whacked after each adaptivePredict(). It cost a little bit
    # more time I think and doesn't save on the overall footprint
    # so it's not worth the complexity.</p>
    #/
    @atn = atn
    @shared_context_cache = shared_context_cache
  end

  def get_cached_context(context)
    return context if @shared_context_cache.nil?
    visited = Map.new
    get_cached_predicton_context(context, @shared_context_cache, visited)
  end
end
