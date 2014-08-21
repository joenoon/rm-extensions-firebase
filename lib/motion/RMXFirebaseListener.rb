class RMXFirebaseListener

  include RMXCommonMethods

  attr_accessor :snapshot, :ref, :callback, :handle, :value_required

  attr_reader :cancel_error

  RMX(self).weak_attr_accessor :callback_owner

  def rmx_dealloc
    if ref && handle
      ref.off(handle)
    end
  end

  def ready?
    @state == :ready
  end

  def cancelled?
    @state == :cancelled
  end

  def stateInfo
    info = []
    # prevent infinite loop if cancelled models point to each other
    return info if @processingCancelInfo
    @processingCancelInfo = true
    info << {
      :ref => @ref.description,
      :state => @state,
      :error => (@cancel_error && @cancel_error.localizedDescription || nil)
    }
    @processingCancelInfo = false
    info
  end

  def start!
    @state = nil
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    cancel_block = lambda do |err|
      @state = :cancelled
      @cancel_error = err
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
          @state = :ready
          RMX(self).trigger(:finished, self)
          # p "ready__"
        end
      end
    end
  end

  def stop!
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    @state = nil
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
