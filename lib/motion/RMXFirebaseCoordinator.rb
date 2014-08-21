class RMXFirebaseCoordinator

  include RMXCommonMethods

  attr_reader :watches

  def initialize
    @watches = {}
    @state = nil

  end

  def stateInfo
    info = []
    # prevent infinite loop if cancelled models point to each other
    return info if @processingCancelInfo
    @processingCancelInfo = true
    watches.values.each do |w|
      info += w.stateInfo
    end
    @processingCancelInfo = false
    info
  end

  def clear!
    RMXFirebase::QUEUE.barrier_async do
      @state = nil
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
    @state == :ready
  end

  def cancelled?
    @state == :cancelled
  end

  def ready!
    RMXFirebase::QUEUE.barrier_async do
      # p "ready!"
      @state = :ready
      RMX(self).trigger(:finished, self)
    end
  end

  def cancelled!
    RMXFirebase::QUEUE.barrier_async do
      # p "cancelled!"
      @state = :cancelled
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
