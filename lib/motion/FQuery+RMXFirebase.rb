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

    event_type = EVENT_TYPES_MAP[_event_type]
    raise "event handler is unknown: #{_event_type.inspect}" unless event_type

    and_then ||= options[:completion]
    raise "event handler is required" unless and_then
    raise "event handler must accept one or two arguments" unless and_then.arity == 1 || and_then.arity == 2

    dealloc_signals = [ rac_willDeallocSignal, and_then.rac_willDeallocSignal ]

    if and_disconnect = options[:disconnect]
      raise ":disconnect handler must not accept any arguments" if and_disconnect && and_disconnect.arity != 1
      dealloc_signals << and_disconnect.owner.rac_willDeallocSignal
    end

    once = options[:once]

    completion = RMX.safe_lambda(and_then, "completion block for #{_event_type.inspect}")

    disconnect = nil
    if and_disconnect
      disconnect = RMX.safe_lambda(and_disconnect, "disconnect block for #{_event_type.inspect}")
    end

    handler = nil
    RMX.synchronized do
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

      @active_handlers ||= []
      @active_handlers << handler
    end

    RACSignal.zip(dealloc_signals.uniq).take(1).subscribeCompleted(-> {
      off(handler)
    })

    handler
  end

  def once(event_type, options={}, &and_then)
    on(event_type, options.merge(:once => true), &and_then)
  end

  def off(handler)
    RMX.synchronized do
      if @active_handlers
        if @active_handlers.delete(handler)
          removeObserverWithHandle(handler)
          # p("remove handle#{handler}")
          true
        end
      end
    end
  end

  def description
    AFHTTPRequestSerializer.serializer.requestWithMethod("GET", URLString: "https://#{repo.repoInfo.host}#{path.toString}", parameters:queryParams.queryObject).URL.absoluteString
  end

end
