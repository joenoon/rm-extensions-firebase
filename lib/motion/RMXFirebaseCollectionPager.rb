class RMXFirebaseCollectionPager

  include RMXCommonMethods

  def range
    RMX(self).sync_ivar(:range)
  end

  def range=(val)
    RMX(self).sync_ivar(:range, val)
    changed!
  end

  def shift_range(add_range)
    r = range || (0..0)
    x = r.first + add_range.first
    y = r.last + add_range.last
    self.range = Range.new(x, y, add_range.exclude_end?)
  end

  def order
    RMX(self).sync_ivar(:order)
  end

  def order=(val)
    RMX(self).sync_ivar(:order, val)
    changed!
  end

  def changed!
    RMX(self).trigger(:changed, self)
  end

end
