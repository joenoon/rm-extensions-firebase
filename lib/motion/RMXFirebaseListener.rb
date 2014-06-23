class RMXFirebaseListener

  include RMXCommonMethods

  attr_accessor :snapshot, :ref, :callback, :handle, :value_required
  RMX(self).weak_attr_accessor :callback_owner

  def rmx_dealloc
    if ref && handle
      ref.off(handle)
    end
  end

  def ready?
    !!@ready
  end

  def cancelled?
    !!@cancelled
  end

  def start!
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    cancel_block = lambda do |err|
      @cancelled = err
      RMX(self).trigger(:cancelled, self)
      RMX(self).trigger(:finished, self)
    end
    @handle = ref.on(:value, { :disconnect => cancel_block }) do |snap|
      RMXFirebase::QUEUE.barrier_async do
        @snapshot = snap
        if value_required && !snap.hasValue?
          cancel_block.call(NSError.errorWithDomain("requirement failure", code:0, userInfo:{
            :error => "requirement_failure"
          }))
        else
          callback.call(snap) if callback && callback_owner
          @ready = true
          RMX(self).trigger(:ready, self)
          RMX(self).trigger(:finished, self)
          # p "ready__"
        end
      end
    end
  end

  def stop!
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    @cancelled = false
    @ready = false
    if ref && handle
      ref.off(handle)
    end
  end

  def hasValue?
    !!(snapshot && snapshot.hasValue?)
  end

  def toValue
    snapshot && snapshot.value
  end

  def attr(keypath)
    valueForKeyPath(keypath)
  end

  def valueForKey(key)
    snapshot && snapshot.valueForKey(key)
  end

  def valueForUndefinedKey(key)
    nil
  end

end
