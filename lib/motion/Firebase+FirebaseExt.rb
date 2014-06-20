class Firebase

  DEBUG_SETVALUE = RMExtensions::Env['rmext_firebase_debug_setvalue'] == '1'

  INTERNAL_QUEUE = Dispatch::Queue.new("FirebaseExt.internal")

  def rmext_object_desc
    "#{super}:#{description}"
  end

  def [](*names)
    if names.length == 0
      childByAutoId
    else
      childByAppendingPath(names.join('/'))
    end
  end

  def limited(limit)
    queryLimitedToNumberOfChildren(limit)
  end

  def starting_at(priority)
    queryStartingAtPriority(priority)
  end

  def ending_at(priority)
    queryEndingAtPriority(priority)
  end

  def rmext_arrayToHash(array)
    hash = {}
    array.each_with_index do |item, i|
      hash[i.to_s] = item
    end
    hash
  end

  def rmext_castValue(value, key=nil)
    if value == true
    elsif value == false
    elsif value.is_a?(NSString)
    elsif value.is_a?(NSNumber)
    elsif value.nil?
      p "FIREBASE_BAD_TYPE FIXED NIL: #{File.join(*[ description, key ].compact.map(&:to_s))}", "!"
      value = {}
    elsif value.is_a?(Array)
      value = rmext_arrayToHash(value)
      p "FIREBASE_BAD_TYPE FIXED ARRAY: #{File.join(*[ description, key ].compact.map(&:to_s))}: #{value.inspect} (type: #{value.className.to_s})", "!"
    elsif value.is_a?(NSDictionary)
      _value = value.dup
      new_value = {}
      _value.keys.each do |k|
        new_value[k.to_s] = rmext_castValue(_value[k], k)
      end
      value = new_value
    else
      p "FIREBASE_BAD_TYPE FATAL: #{File.join(*[ description, key ].compact.map(&:to_s))}: #{value.inspect} (type: #{value.className.to_s})", "!"
    end
    # always return the value, corrected or not
    value
  end

  def rmext_setValue(value, andPriority:priority)
    # value = rmext_castValue(value)
    setValue(value, andPriority:priority)
  end
  def rmext_setValue(value)
    # value = rmext_castValue(value)
    setValue(value)
  end
  def rmext_onDisconnectSetValue(value)
    value = rmext_castValue(value)
    onDisconnectSetValue(value)
  end

  alias_method 'orig_setValue', 'setValue'
  alias_method 'orig_setValueAndPriority', 'setValue:andPriority'

  def setValue(value, andPriority:priority)
    if DEBUG_SETVALUE
      p description, "setValue:andPriority", value, priority
    end
    value = rmext_castValue(value)
    orig_setValueAndPriority(value, priority)
  end
  def setValue(value)
    if DEBUG_SETVALUE
      p description, "setValue:", value
    end
    value = rmext_castValue(value)
    orig_setValue(value)
  end

  def self.dispatchQueue
    INTERNAL_QUEUE
  end

end

Firebase.setDispatchQueue(Firebase::INTERNAL_QUEUE.dispatch_object)
