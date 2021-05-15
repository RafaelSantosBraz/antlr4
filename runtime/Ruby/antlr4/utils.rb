# Copyright (c) 2012-2017 The ANTLR Project. All rights reserved.
# Use of this file is governed by the BSD 3-clause license that
# can be found in the LICENSE.txt file in the project root.
#

require "set"

# encoding used to convert from int to str
DECODE_ENCODING = Encoding::UTF_8

# encoding used for reading files
FILE_ENCODING = Encoding::UTF_8

# custom Set to handle @is_inside_set of ATNConfig
class CustomSetForATNConfigSet
  def initialize
    @_set = Set.new
  end

  def add(value)
    existing = find_eql(value)
    return existing unless existing.nil?
    value.is_inside_set = true
    @_set.add(value)
    value.is_inside_set = false
    value
  end

  def include?(value)
    value.is_inside_set = true
    resp = @_set.include?(value)
    value.is_inside_set = false
    resp
  end

  # intuitive name for "get"
  def find_eql(value)
    value.is_inside_set = true
    existing = @_set.find { |v|
      v.is_inside_set = true
      resp = v.eql? value
      v.is_inside_set = false
      resp
    }
    value.is_inside_set = false
    existing
  end

  def get(value)
    find_eql?(value)
  end

  def values
    @_set.to_a
  end

  def to_s
    @_set.to_s
  end

  def size
    @_set.size
  end
end

def init_array(size, value)
  tmp = []
  tmp[size - 1] = value
  tmp
end

class BitSet
  attr_accessor(:data)

  def initialize
    @data = []
  end

  def add(value)
    @data[value] = true
  end

  def orr(set)
    bits = self
    sel.data.each_index { |alt|
      bits.add(alt)
    }
  end

  def remove(value)
    @data[value] = nil
  end

  def include?(value)
    @data[value] == true
  end

  def values
    keys = []
    @data.each_index { |alt|
      keys << alt if alt == true
    }
    keys
  end

  def min_value
    values().min
  end

  def hash
    values.hash
  end

  def eql?(other)
    return false unless other.is_a? BitSet
    self.hash == other.hash
  end

  def to_s
    "{#{values().join(", ")}}"
  end

  def size
    values.size
  end
end

class Map
  attr_accessor(:hash_function, :equals_function)

  def initialize(hash_function_proc = nil, equals_function_proc = nil)
    @hash_function = hash_function_proc
    @equals_function = equals_function_proc
    @_the_hash = {}
  end

  def apply_hash_eql_to_obj(obj)
    obj_hash_cache = obj.method(:hash)
    obj_eql_cache = obj.method(:eql?)
    cache = [obj_hash_cache, obj_eql_cache]
    if not obj.nil? and not obj.frozen? and not @hash_function.nil?
      obj.define_singleton_method(:hash, @hash_function)
    end
    if not obj.nil? and not obj.frozen? and not @equals_function.nil?
      obj.define_singleton_method(:eql?, @equals_function)
    end
    cache
  end

  def return_hash_eql_to_obj(obj, cache)
    if not obj.nil? and not obj.frozen?
      obj.define_singleton_method(:hash, cache[0])
      obj.define_singleton_method(:eql?, cache[1])
    end
  end

  def apply_hash_eql_to_the_hash
    hash_eql_cache = {}
    @_the_hash.each_key { |k|
      if not k.nil? and not k.frozen?
        hash_eql_cache[k] = [k.method(:hash), k.method(:eql?)]
        k.define_singleton_method(:hash, @hash_function)
        k.define_singleton_method(:eql?, @equals_function)
      end
    }
    hash_eql_cache
  end

  def return_hash_eql_to_the_hash(hash_eql_cache)
    @_the_hash.each_key { |k|
      if hash_eql_cache.include?(k)
        (h, e) = hash_eql_cache[k]
        k.define_singleton_method(:hash, h)
        k.define_singleton_method(:eql?, e)
      end
    }
  end

  def put(key, value)
    existing = get(key)
    if existing.nil?
      key_cache = apply_hash_eql_to_obj(key)
      the_hash_cache = apply_hash_eql_to_the_hash()
      @_the_hash[key] = value
      return_hash_eql_to_the_hash(the_hash_cache)
      return_hash_eql_to_obj(key, key_cache)
      return value
    end
    key_cache = apply_hash_eql_to_obj(key)
    the_hash_cache = apply_hash_eql_to_the_hash()
    @_the_hash[key] = value
    return_hash_eql_to_the_hash(the_hash_cache)
    return_hash_eql_to_obj(key, key_cache)
    existing
  end

  def include_key?(key)
    key_cache = apply_hash_eql_to_obj(key)
    the_hash_cache = apply_hash_eql_to_the_hash()
    resp = @_the_hash.include?(key)
    return_hash_eql_to_the_hash(the_hash_cache)
    return_hash_eql_to_obj(key, key_cache)
    resp
  end

  def get(key)
    obj_cache = apply_hash_eql_to_obj(obj)
    the_hash_cache = apply_hash_eql_to_the_hash()
    resp = @_the_hash[key]
    return_hash_eql_to_the_hash(the_hash_cache)
    return_hash_eql_to_obj(obj, obj_cache)
    resp
  end

  def entries
    @_the_hash.entries
  end

  def get_keys
    @_the_hash.keys
  end

  def get_values
    @_the_hash.values
  end

  def to_s
    @_the_hash.to_s
  end

  def size
    @_the_hash.size
  end
end

class AltDict
  attr_accessor(:data)

  def initialize
    @data = {}
  end

  def get(key)
    @data[key]
  end

  def put(key, value)
    @data[key] = value
  end

  def values
    @data.values
  end
end
