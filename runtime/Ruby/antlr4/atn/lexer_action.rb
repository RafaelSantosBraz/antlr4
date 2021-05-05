# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

class LexerActionType
  # The type of a {@link LexerChannelAction} action.
  CHANNEL = 0
  # The type of a {@link LexerCustomAction} action.
  CUSTOM = 1
  # The type of a {@link LexerModeAction} action.
  MODE = 2
  # The type of a {@link LexerMoreAction} action.
  MORE = 3
  # The type of a {@link LexerPopAction} action.
  POP_MODE = 4
  # The type of a {@link LexerPushAction} action.
  PUSH_MODE = 5
  # The type of a {@link LexerSkipAction} action.
  SKIP = 6
  # The type of a {@link LexerTypeAction} action.
  TYPE = 7
end

class LexerAction
  attr_accessor(:action_type, :is_position_dependent)

  def initialize(action)
    @action_type = action
    @is_position_dependent = false
  end

  def hash
    @action_type.hash
  end
end

#
# Implements the {@code skip} lexer action by calling {@link Lexer//skip}.
#
# <p>The {@code skip} command does not have any parameters, so this action is
# implemented as a singleton instance exposed by {@link //INSTANCE}.</p>
#/
class LexerSkipAction < LexerAction

  # Provides a singleton instance of this parameterless lexer action.
  INSTANCE = LexerSkipAction.new

  def initialize
    super(LexerActionType::SKIP)
  end

  def execute(lexer)
    lexer.skip()
  end

  def to_s
    "skip"
  end
end

#
# Implements the {@code type} lexer action by calling {@link Lexer//setType}
# with the assigned type
#/
class LexerTypeAction < LexerAction
  attr_accessor(:type)

  def initialize(type)
    super(LexerActionType::TYPE)
    @type = type
  end

  def execute(lexer)
    lexer.type = type
  end

  def hash
    [@action_type, @type].hash
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a?(LexerTypeAction)
    @type == other.type
  end

  def to_s
    "type(#{@type})"
  end
end

#
# Implements the {@code pushMode} lexer action by calling
# {@link Lexer//pushMode} with the assigned mode
#/
class LexerPushModeAction < LexerAction
  attr_accessor(:mode)

  def initialize(mode)
    super(LexerActionType::PUSH_MODE)
    @mode = mode
  end

  #
  # <p>This action is implemented by calling {@link Lexer//pushMode} with the
  # value provided by {@link //getMode}.</p>
  #/
  def execute(lexer)
    lexer.push_mode(@mode)
  end

  def hash
    [@action_type, @mode].hash
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? LexerPushModeAction
    @mode == other.mode
  end

  def to_s
    "pushMode(#{@mode})"
  end
end

#
# Implements the {@code popMode} lexer action by calling {@link Lexer//popMode}.
#
# <p>The {@code popMode} command does not have any parameters, so this action is
# implemented as a singleton instance exposed by {@link //INSTANCE}.</p>
#/
class LexerPopModeAction < LexerAction
  INSTANCE = LexerPopModeAction.new

  def initialize
    super(LexerActionType::POP_MODE)
  end

  #
  # <p>This action is implemented by calling {@link Lexer//popMode}.</p>
  #
  def execute(lexer)
    lexer.pop_mode()
  end

  def to_s
    "popMode"
  end
end

#
# Implements the {@code more} lexer action by calling {@link Lexer//more}.
#
# <p>The {@code more} command does not have any parameters, so this action is
# implemented as a singleton instance exposed by {@link //INSTANCE}.</p>
#/
class LexerMoreAction < LexerAction
  INSTANCE = LexerMoreAction.new

  def initialize
    super(LexerActionType::MORE)
  end

  #
  # <p>This action is implemented by calling {@link Lexer//popMode}.</p>
  #/
  def execute(lexer)
    lexer.pop_more()
  end

  def to_s
    "more"
  end
end

#
# Implements the {@code mode} lexer action by calling {@link Lexer//mode} with
# the assigned mode
#/

class LexerModeAction < LexerAction
  attr_accessor(:mode)

  def initialize(mode)
    super(LexerActionType::MODE)
    @mode = mode
  end

  #
  # <p>This action is implemented by calling {@link Lexer//mode} with the
  # value provided by {@link //getMode}.</p>
  #/
  def execute(lexer)
    lexer.mode(mode)
  end

  def hash
    [@action_type, @mode].hash
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? LexerModeAction
    @mode == other.mode
  end

  def to_s
    "mode(#{@mode})"
  end
end

#
# Executes a custom lexer action by calling {@link Recognizer//action} with the
# rule and action indexes assigned to the custom action. The implementation of
# a custom action is added to the generated code for the lexer in an override
# of {@link Recognizer//action} when the grammar is compiled.
#
# <p>This class may represent embedded actions created with the <code>{...}</code>
# syntax in ANTLR 4, as well as actions created for lexer commands where the
# command argument could not be evaluated when the grammar was compiled.</p>
#/
class LexerCustomAction < LexerAction
  attr_accessor(:rule_index, :action_index)
  #
  # Constructs a custom lexer action with the specified rule and action
  # indexes.
  #
  # @param ruleIndex The rule index to use for calls to
  # {@link Recognizer//action}.
  # @param actionIndex The action index to use for calls to
  # {@link Recognizer//action}.
  #/
  def initialize(rule_index, action_index)
    super(LexerActionType::CUSTOM)
    @rule_index = rule_index
    @action_index = action_index
    @is_position_dependent = true
  end

  #
  # <p>Custom actions are implemented by calling {@link Lexer//action} with the
  # appropriate rule and action indexes.</p>
  #/
  def execute
    lexer.action(nil, @rule_index, @action_index)
  end

  def hash
    [@action_type, @rule_index, @action_index].hash
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? LexerCustomAction
    @rule_index == other.rule_index and @action_index == other.action_index
  end
end

#
# Implements the {@code channel} lexer action by calling
# {@link Lexer//setChannel} with the assigned channel.
# Constructs a new {@code channel} action with the specified channel value.
# @param channel The channel value to pass to {@link Lexer//setChannel}
#/
class LexerChannelAction < LexerAction
  attr_accessor(:channel)

  def initialize(channel)
    super(LexerActionType::CHANNEL)
    @channel = channel
  end

  #
  # <p>This action is implemented by calling {@link Lexer//setChannel} with the
  # value provided by {@link //getChannel}.</p>
  #/
  def execute(lexer)
    lexer.channel = @channel
  end

  def hash
    [@action_type, @channel].hash
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? LexerChannelAction
    @channel == other.channel
  end

  def to_s
    "channel(#{@channel})"
  end
end

#
# This implementation of {@link LexerAction} is used for tracking input offsets
# for position-dependent actions within a {@link LexerActionExecutor}.
#
# <p>This action is not serialized as part of the ATN, and is only required for
# position-dependent lexer actions which appear at a location other than the
# end of a rule. For more information about DFA optimizations employed for
# lexer actions, see {@link LexerActionExecutor//append} and
# {@link LexerActionExecutor//fixOffsetBeforeMatch}.</p>
#
# Constructs a new indexed custom action by associating a character offset
# with a {@link LexerAction}.
#
# <p>Note: This class is only required for lexer actions for which
# {@link LexerAction//isPositionDependent} returns {@code true}.</p>
#
# @param offset The offset into the input {@link CharStream}, relative to
# the token start index, at which the specified lexer action should be
# executed.
# @param action The lexer action to execute at a particular offset in the
# input {@link CharStream}.
#/
class LexerIndexedCustomAction < LexerAction
  attr_accessor(:offset, :action)

  def initialize(offset, action)
    super(action.action_type)
    @offset = offset
    @action = action
    @is_position_dependent = true
  end

  #
  # <p>This method calls {@link //execute} on the result of {@link //getAction}
  # using the provided {@code lexer}.</p>
  #/
  def execute(lexer)
    # assume the input stream position was properly set by the calling code
    @action.execute(lexer)
  end

  def hash
    [@action_type, @offset, @action].hash
  end

  def eql?(other)
    return true if self == other
    return false unless other.is_a? LexerIndexedCustomAction
    @offset == other.offset and @action == other.action
  end
end
