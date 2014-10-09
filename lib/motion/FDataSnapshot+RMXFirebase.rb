class FDataSnapshot

  def hasValue?
    !value.nil?
  end

  def attr(keypath)
    valueForKeyPath(keypath)
  end

  def valueForKey(key)
    if v = value
      v[key]
    end
  end

  def valueForUndefinedKey(key)
    nil
  end

end
