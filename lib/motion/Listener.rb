module FirebaseExt

  class Listener

    include RMExtensions::CommonMethods

    attr_accessor :snapshot, :ref, :callback, :handle, :value_required
    rmext_weak_attr_accessor :callback_owner

    def rmext_dealloc
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
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      cancel_block = lambda do |err|
        @cancelled = err
        rmext_trigger(:cancelled, self)
        rmext_trigger(:finished, self)
      end
      @handle = ref.on(:value, { :disconnect => cancel_block }) do |snap|
        QUEUE.barrier_async do
          @snapshot = snap
          if value_required && !snap.hasValue?
            cancel_block.call(NSError.errorWithDomain("requirement failure", code:0, userInfo:{
              :error => "requirement_failure"
            }))
          else
            callback.call(snap) if callback && callback_owner
            @ready = true
            rmext_trigger(:ready, self)
            rmext_trigger(:finished, self)
            # p "ready__"
          end
        end
      end
    end

    def stop!
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
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

end
