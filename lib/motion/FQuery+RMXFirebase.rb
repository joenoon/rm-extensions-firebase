class FQuery

  RECURSIVE_LOCK = NSRecursiveLock.new

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

  def on(event_type, options={}, &and_then)
    completion = and_then || options[:completion]
    disconnect = options[:disconnect]

    once = options[:once]

    sig = case event_type
    when :child_added, :added
      if once
        rac_addedOnceSignal
      else
        rac_addedSignal
      end
    when :child_moved, :moved
      if once
        rac_movedOnceSignal
      else
        rac_movedSignal
      end
    when :child_changed, :changed
      if once
        rac_changedOnceSignal
      else
        rac_changedSignal
      end
    when :child_removed, :removed
      if once
        rac_removedOnceSignal
      else
        rac_removedSignal
      end
    when :value
      if once
        rac_valueOnceSignal
      else
        rac_valueSignal
      end
    end

    dis = nil

    if completion
      safe_completion = RMX.safe_lambda(completion, "completion block for #{event_type.inspect}")
      sig = sig.takeUntil(completion.owner.rac_willDeallocSignal)
      if disconnect
        safe_disconnect = RMX.safe_lambda(disconnect, "disconnect block for #{event_type.inspect}")
        dis = sig.subscribeNext(safe_completion, error:safe_disconnect)
      else
        dis = sig.subscribeNext(safe_completion)
      end
    end

    dis
  end

  def once(event_type, options={}, &and_then)
    on(event_type, options.merge(:once => true), &and_then)
  end

  def description
    AFHTTPRequestSerializer.serializer.requestWithMethod("GET", URLString: "https://#{repo.repoInfo.host}#{path.toString}", parameters:queryParams.queryObject).URL.absoluteString
  end

  # Value sends curr
  def rac_valueSignal
    RECURSIVE_LOCK.lock
    @_rac_valueSignal_autoreconnector = recon ||= {}
    if pub = recon[:publisher] and pub.serialDisposable.isDisposed.boolValue
      # NSLog("sig dead, clear")
      @_rac_valueSignal_autoreconnector.clear
    end
    recon[:signal] = signal ||= RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = observeEventType(FEventTypeValue, withBlock:->(curr) {
        subscriber.sendNext(curr)
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("createSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("disposableWithBlock removeObserverWithHandle(#{handler})")
        removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    }.weak!)
    recon[:publisher] = publisher ||= signal.multicast(RACReplaySubject.replaySubjectWithCapacity(1))
    recon[:connection] = connection ||= publisher.autoconnect
    RECURSIVE_LOCK.unlock
    connection
  end

  # ChildAdded sends [ curr, prev ]
  def rac_addedSignal
    RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = observeEventType(FEventTypeChildAdded, andPreviousSiblingWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_addedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("rac_addedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    }.weak!)
  end

  # ChildMoved sends [ curr, prev ]
  def rac_movedSignal
    RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = observeEventType(FEventTypeChildMoved, andPreviousSiblingWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_movedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("rac_movedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    }.weak!)
  end

  # ChildChanged sends [ curr, prev ]
  def rac_changedSignal
    RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = observeEventType(FEventTypeChildChanged, andPreviousSiblingWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_changedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("rac_changedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    }.weak!)
  end

  # ChildRemoved sends curr
  def rac_removedSignal
    RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = observeEventType(FEventTypeChildRemoved, withBlock:->(curr) {
        subscriber.sendNext(curr)
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_removedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("rac_removedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    }.weak!)
  end

  # once signals

  def rac_valueOnceSignal
    rac_valueSignal.take(1)
  end

  def rac_addedOnceSignal
    rac_addedSignal.take(1)
  end

  def rac_movedOnceSignal
    rac_movedSignal.take(1)
  end

  def rac_changedOnceSignal
    rac_changedSignal.take(1)
  end
  def rac_removedOnceSignal
    rac_removedSignal.take(1)
  end

end
