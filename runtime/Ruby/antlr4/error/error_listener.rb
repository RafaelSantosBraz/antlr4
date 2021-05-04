# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.

#
# Provides an empty default implementation of {@link ANTLRErrorListener}. The
# default implementation of each method does nothing, but can be overridden as
# necessary.
#/

class ErrorListener
  def syntax_error(recognizer, offending_symbol, line, column, msg, e)
  end

  def report_ambiguity(recognizer, dfa, start_index, stop_index, exact,
                       ambig_alts, configs)
  end

  def report_attempting_full_context(recognizer, dfa, start_index, stop_index,
                                     conflicting_alts, configs)
  end

  def report_context_sensitivity(recognizer, dfa, start_index, stop_index,
                                 prediction, configs)
  end
end

#
# {@inheritDoc}
#
# <p>
# This implementation prints messages to {@link System//err} containing the
# values of {@code line}, {@code charPositionInLine}, and {@code msg} using
# the following format.</p>
#
# <pre>
# line <em>line</em>:<em>charPositionInLine</em> <em>msg</em>
# </pre>
#
#/
class ConsoleErrorListener < ErrorListener

  #
  # Provides a default instance of {@link ConsoleErrorListener}.
  #
  INSTANCE = ConsoleErrorListener.new

  def syntax_error(recognizer, offending_symbol, line, column, msg, e)
    STDERR.puts "line #{line}:#{column} #{msg}"
  end
end

class ProxyErrorListener < ErrorListener
  attr_accessor(:delegates)

  def initialize(delegates)
    raise(Exception, "delegates") if delegates.nil?
    @delegates = delegates
  end

  def syntax_error(recognizer, offending_symbol, line, column, msg, e)
    @delegates.each { |d|
      d.syntax_error(recognizer, offending_symbol, line, column, msg, e)
    }
  end

  def report_ambiguity(recognizer, dfa, start_index, stop_index, exact,
                       ambig_alts, configs)
    @delegates.each { |d|
      d.report_ambiguity(recognizer, dfa, start_index, stop_index, exact,
                         ambig_alts, configs)
    }

    def report_attempting_full_context(recognizer, dfa, start_index, stop_index,
                                       conflicting_alts, configs)
      @delegates.each { |d|
        d.report_attempting_full_context(recognizer, dfa, start_index,
                                         stop_index, conflicting_alts, configs)
      }
    end

    def report_context_sensitivity(recognizer, dfa, start_index, stop_index,
                                   prediction, configs)
      @delegates.each { |d|
        d.report_context_sensitivity(recognizer, dfa, start_index, stop_index,
                                     prediction, configs)
      }
    end
  end
end
