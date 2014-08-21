class FQuery

  EVENT_TYPES_MAP = {
    :child_added => FEventTypeChildAdded,
    :added => FEventTypeChildAdded,
    :child_moved => FEventTypeChildMoved,
    :moved => FEventTypeChildMoved,
    :child_changed => FEventTypeChildChanged,
    :changed => FEventTypeChildChanged,
    :child_removed => FEventTypeChildRemoved,
    :removed => FEventTypeChildRemoved,
    :value => FEventTypeValue
  }

  def rmx_object_desc
    "#{super}:#{description}"
  end

  def limited(limit)
    queryLimitedToNumberOfChildren(limit)
  end

  def starting_at(priority)
    queryStartingAtPriority(priority)
  end

  def ending_at(priority)
    queryEndingAtPriority(priority)
  end

  def on(_event_type, options={}, &and_then)
    and_then ||= options[:completion]
    raise "event handler is required" unless and_then
    raise "event handler must accept one or two arguments" unless and_then.arity == 1 || and_then.arity == 2
    completion = RMX.safe_block(and_then)

    event_type = EVENT_TYPES_MAP[_event_type]
    raise "event handler is unknown: #{_event_type.inspect}" unless event_type

    _disconnect_block = options[:disconnect]
    raise ":disconnect handler must not accept any arguments" if _disconnect_block && _disconnect_block.arity != 1
    disconnect_block = nil
    if _disconnect_block
      disconnect_inner_block = RMX.safe_block(_disconnect_block)
      disconnect_block = lambda do |err|
        disconnect_inner_block.call(err)
      end.weak!
    end
    handler = nil
    if and_then.arity == 1
      inner_block = RMX.safe_block(lambda do |snap|
        completion.call(snap)
      end)
      wrapped_block = lambda do |snap|
        inner_block.call(snap)
      end.weak!
      if disconnect_block
        if options[:once]
          RMXFirebase::INTERNAL_QUEUE.sync do
            handler = observeSingleEventOfType(event_type, withBlock:wrapped_block, withCancelBlock:disconnect_block)
          end
        else
          RMXFirebase::INTERNAL_QUEUE.sync do
            handler = observeEventType(event_type, withBlock:wrapped_block, withCancelBlock:disconnect_block)
          end
        end
      else
        if options[:once]
          RMXFirebase::INTERNAL_QUEUE.sync do
            handler = observeSingleEventOfType(event_type, withBlock:wrapped_block)
          end
        else
          RMXFirebase::INTERNAL_QUEUE.sync do
            handler = observeEventType(event_type, withBlock:wrapped_block)
          end
        end
      end
    else
      inner_block = RMX.safe_block(lambda do |snap, prev|
        completion.call(snap, prev)
      end)
      wrapped_block = lambda do |snap, prev|
        inner_block.call(snap, prev)
      end.weak!
      if disconnect_block
        if options[:once]
          RMXFirebase::INTERNAL_QUEUE.sync do
            handler = observeSingleEventOfType(event_type, andPreviousSiblingNameWithBlock:wrapped_block, withCancelBlock:disconnect_block)
          end
        else
          RMXFirebase::INTERNAL_QUEUE.sync do
            handler = observeEventType(event_type, andPreviousSiblingNameWithBlock:wrapped_block, withCancelBlock:disconnect_block)
          end
        end
      else
        if options[:once]
          RMXFirebase::INTERNAL_QUEUE.sync do
            handler = observeSingleEventOfType(event_type, andPreviousSiblingNameWithBlock:wrapped_block)
          end
        else
          RMXFirebase::INTERNAL_QUEUE.sync do
            handler = observeEventType(event_type, andPreviousSiblingNameWithBlock:wrapped_block)
          end
        end
      end
    end
    unless options[:once]
      @_outstanding_handlers ||= OutstandingHandlers.new(self)
      @_outstanding_handlers << handler
    end
    handler
  end

  class OutstandingHandlers

    RMX(self).weak_attr_accessor :scope

    def initialize(_scope)
      self.scope = _scope
      @handlers = []
    end

    def <<(handler)
      @handlers << handler
    end

    def handlers
      @handlers
    end

    def off(handle=nil)
      if s = scope
        if _handle = @handlers.delete(handle)
          # p s.rmx_object_desc, "remove handle", _handle
          RMXFirebase::INTERNAL_QUEUE.sync do
            s.removeObserverWithHandle(_handle)
          end
        else
          _handlers = @handlers.dup
          while _handlers.size > 0
            _handle = _handlers.shift
            off(_handle)
          end
        end
      end
    end

    def dealloc
      off
      super
    end
  end

  def once(event_type, options={}, &and_then)
    on(event_type, options.merge(:once => true), &and_then)
  end

  def _off(handle)
    if @_outstanding_handlers
      @_outstanding_handlers.off(handle)
    end
    self
  end

  def off(handle)
    RMXFirebase::QUEUE.barrier_async do
      _off(handle)
    end
    self
  end

  def description
    AFHTTPRequestSerializer.serializer.requestWithMethod("GET", URLString: "https://#{repo.repoInfo.host}#{path.toString}", parameters:queryParams.queryObject).URL.absoluteString
  end

end
