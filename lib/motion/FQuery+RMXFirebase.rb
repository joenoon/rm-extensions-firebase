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

  #                                  A#  ONCE?  DISC?
  TYPE_ONE_ARG_ONCE_DO_DISCONNECT = [ 1, true,  true  ]
  TYPE_ONE_ARG_ONCE_NO_DISCONNECT = [ 1, true,  false ]
  TYPE_ONE_ARG_CONT_DO_DISCONNECT = [ 1, false, true  ]
  TYPE_ONE_ARG_CONT_NO_DISCONNECT = [ 1, false, false ]
  TYPE_TWO_ARG_ONCE_DO_DISCONNECT = [ 2, true,  true  ]
  TYPE_TWO_ARG_ONCE_NO_DISCONNECT = [ 2, true,  false ]
  TYPE_TWO_ARG_CONT_DO_DISCONNECT = [ 2, false, true  ]
  TYPE_TWO_ARG_CONT_NO_DISCONNECT = [ 2, false, false ]

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

    completion = RMX.safe_lambda(and_then, "#{description} competion block for #{_event_type.inspect}")
    raise "event handler must accept one or two arguments" unless completion.arity == 1 || completion.arity == 2

    disconnect = options[:disconnect] ? RMX.safe_lambda(options[:disconnect], "#{description} disconnect block for #{_event_type.inspect}") : nil
    raise ":disconnect handler must not accept any arguments" if disconnect && disconnect.arity != 1

    event_type = EVENT_TYPES_MAP[_event_type]
    raise "event handler is unknown: #{_event_type.inspect}" unless event_type

    once = options[:once]

    handler = nil
    RMXFirebase::INTERNAL_QUEUE.sync do
      handler = case [ completion.arity, !!once, !!disconnect ]
      when TYPE_ONE_ARG_ONCE_DO_DISCONNECT
        observeSingleEventOfType(event_type, withBlock:completion, withCancelBlock:disconnect)
      when TYPE_ONE_ARG_CONT_DO_DISCONNECT
        observeEventType(event_type, withBlock:completion, withCancelBlock:disconnect)
      when TYPE_ONE_ARG_ONCE_NO_DISCONNECT
        observeSingleEventOfType(event_type, withBlock:completion)
      when TYPE_ONE_ARG_CONT_NO_DISCONNECT
        observeEventType(event_type, withBlock:completion)
      when TYPE_TWO_ARG_ONCE_DO_DISCONNECT
        observeSingleEventOfType(event_type, andPreviousSiblingNameWithBlock:completion, withCancelBlock:disconnect)
      when TYPE_TWO_ARG_CONT_DO_DISCONNECT
        observeEventType(event_type, andPreviousSiblingNameWithBlock:completion, withCancelBlock:disconnect)
      when TYPE_TWO_ARG_ONCE_NO_DISCONNECT
        observeSingleEventOfType(event_type, andPreviousSiblingNameWithBlock:completion)
      when TYPE_TWO_ARG_CONT_NO_DISCONNECT
        observeEventType(event_type, andPreviousSiblingNameWithBlock:completion)
      end
    end

    unless once
      RMX.synchronized do
        @_outstanding_handlers ||= OutstandingHandlers.new(self)
        @_outstanding_handlers << handler
      end
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
            # NSLog("remove #{_handle}")
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

    def rmx_dealloc
      off
    end
  end

  def once(event_type, options={}, &and_then)
    on(event_type, options.merge(:once => true), &and_then)
  end

  def off(handle)
    RMX.synchronized do
      if @_outstanding_handlers
        @_outstanding_handlers.off(handle)
      end
    end
    self
  end

  def description
    AFHTTPRequestSerializer.serializer.requestWithMethod("GET", URLString: "https://#{repo.repoInfo.host}#{path.toString}", parameters:queryParams.queryObject).URL.absoluteString
  end

end
