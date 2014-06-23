class RMXFirebaseCoordinator

  include RMXCommonMethods

  attr_reader :watches

  def initialize
    @watches = {}
  end

  def clear!
    RMXFirebase::QUEUE.barrier_async do
      @cancelled = false
      @ready = false
      keys = watches.keys.dup
      while keys.size > 0
        name = keys.shift
        watch = watches[name]
        watch.stop!
      end
      watches.clear
    end
    self
  end

  def ready?
    !!@ready
  end

  def cancelled?
    !!@cancelled
  end

  def ready!
    RMXFirebase::QUEUE.barrier_async do
      @ready = true
      RMX(self).trigger(:ready, self)
      RMX(self).trigger(:finished, self)
    end
  end

  def cancelled!
    RMXFirebase::QUEUE.barrier_async do
      @cancelled = true
      RMX(self).trigger(:cancelled, self)
      RMX(self).trigger(:finished, self)
    end
  end

  def stub(name)
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    watches[name] ||= RMXFirebaseListener.new
  end

  def watch(name, ref, opts={}, &block)
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    data = RMXFirebaseListener.new
    data.ref = ref
    if opts[:required]
      data.value_required = true
    end
    unless block.nil?
      data.callback = block.weak!
      data.callback_owner = block.owner
    end
    if current = watches[name]
      if current == data || current.description == data.description
        return
      end
      current.stop!
      RMX(current).off(:finished, self)
    end
    watches[name] = data
    RMX(data).on(:finished, :queue => RMXFirebase::QUEUE) do
      RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
      readies = 0
      cancelled = 0
      size = watches.size
      watches.each_pair do |k, v|
        if v.ready?
          readies += 1
        elsif v.cancelled?
          cancelled += 1
          break
        end
      end
      if cancelled > 0
        cancelled!
      elsif readies == size
        ready!
      end
    end
    data.start!
    data
  end

  def attr(keypath)
    valueForKeyPath(keypath)
  end

  def valueForKey(key)
    watches[key]
  end

  def valueForUndefinedKey(key)
    nil
  end

end
