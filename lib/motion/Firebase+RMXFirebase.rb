class Firebase

  DEBUG_SETVALUE = RMX::Env['rmx_firebase_debug_setvalue'] == '1'

  def rmx_object_desc
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

  def starting_at(priority, child_name=nil)
    if child_name
      queryStartingAtPriority(priority, andChildName:child_name)
    else
      queryStartingAtPriority(priority)
    end
  end

  def ending_at(priority, child_name=nil)
    if child_name
      queryEndingAtPriority(priority, andChildName:child_name)
    else
      queryEndingAtPriority(priority)
    end
  end

  def rmx_arrayToHash(array)
    hash = {}
    array.each_with_index do |item, i|
      hash[i.to_s] = item
    end
    hash
  end

  def rmx_castValue(value, key=nil)
    if value == true
    elsif value == false
    elsif value.is_a?(NSString)
    elsif value.is_a?(NSNumber)
    elsif value.nil?
      p "FIREBASE_BAD_TYPE FIXED NIL: #{File.join(*[ description, key ].compact.map(&:to_s))}", "!"
      value = {}
    elsif value.is_a?(Array)
      value = rmx_arrayToHash(value)
      p "FIREBASE_BAD_TYPE FIXED ARRAY: #{File.join(*[ description, key ].compact.map(&:to_s))}: #{value.inspect} (type: #{value.className.to_s})", "!"
    elsif value.is_a?(NSDictionary)
      _value = value.dup
      new_value = {}
      _value.keys.each do |k|
        new_value[k.to_s] = rmx_castValue(_value[k], k)
      end
      value = new_value
    else
      p "FIREBASE_BAD_TYPE FATAL: #{File.join(*[ description, key ].compact.map(&:to_s))}: #{value.inspect} (type: #{value.className.to_s})", "!"
    end
    # always return the value, corrected or not
    value
  end

  alias_method 'orig_setValue', 'setValue'
  alias_method 'orig_setValueAndPriority', 'setValue:andPriority'
  alias_method 'orig_setValueAndPriorityCompletionBlock', 'setValue:andPriority:withCompletionBlock'

  def setValue(value, andPriority:priority, withCompletionBlock:block)
    if DEBUG_SETVALUE
      p description, "setValue:andPriority:withCompletionBlock", value, priority
    end
    value = rmx_castValue(value)
    orig_setValueAndPriorityCompletionBlock(value, priority, block)
  end
  def setValue(value, andPriority:priority)
    if DEBUG_SETVALUE
      p description, "setValue:andPriority", value, priority
    end
    value = rmx_castValue(value)
    orig_setValueAndPriority(value, priority)
  end
  def setValue(value)
    if DEBUG_SETVALUE
      p description, "setValue:", value
    end
    value = rmx_castValue(value)
    orig_setValue(value)
  end

end
