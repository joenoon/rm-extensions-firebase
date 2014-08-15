class RMXFirebaseCollectionPager

  include RMXCommonMethods

  def starting_at
    RMX(self).sync_ivar(:starting_at)
  end

  def starting_at=(val)
    RMX(self).sync_ivar(:starting_at, val)
    changed!
  end

  def ending_at
    RMX(self).sync_ivar(:ending_at)
  end

  def ending_at=(val)
    RMX(self).sync_ivar(:ending_at, val)
    changed!
  end

  def limit
    RMX(self).sync_ivar(:limit)
  end

  def limit=(val)
    RMX(self).sync_ivar(:limit, val)
    changed!
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
