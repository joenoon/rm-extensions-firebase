class RMXFirebaseCollectionPager

  RECURSIVE_LOCK = NSRecursiveLock.new

  include RMXCommonMethods

  def range
    RECURSIVE_LOCK.lock
    res = @range
    RECURSIVE_LOCK.unlock
    res
  end

  def range=(val)
    RECURSIVE_LOCK.lock
    @range = val
    RECURSIVE_LOCK.unlock
    changed!
  end

  def shift_range(add_range)
    r = range || (0..0)
    x = r.first + add_range.first
    y = r.last + add_range.last
    self.range = Range.new(x, y, add_range.exclude_end?)
  end

  def order
    RECURSIVE_LOCK.lock
    res = @order
    RECURSIVE_LOCK.unlock
    res
  end

  def order=(val)
    RECURSIVE_LOCK.lock
    @order = val
    RECURSIVE_LOCK.unlock
    changed!
  end

  def changed!
    rac_valueSignal.sendNext(self)
  end

  def rac_valueSignal
    RECURSIVE_LOCK.lock
    rac_valueSignal = @rac_valueSignal ||= RACReplaySubject.replaySubjectWithCapacity(1)
    RECURSIVE_LOCK.unlock
    rac_valueSignal
  end

end
