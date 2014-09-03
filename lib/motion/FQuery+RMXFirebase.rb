class FQuery

  RECURSIVE_LOCK = NSRecursiveLock.new

  Dispatch.once do
    $firebase_valueSignals = {}
  end

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

  def description
    AFHTTPRequestSerializer.serializer.requestWithMethod("GET", URLString: "https://#{repo.repoInfo.host}#{path.toString}", parameters:queryParams.queryObject).URL.absoluteString
  end

  # Value sends curr
  def rac_valueSignal
    self.class.rac_valueSignal(self)
  end
  def self.rac_valueSignal(ref)
    RACSignal.createSignal(->(subscriber) {
      RECURSIVE_LOCK.lock
      hash = $firebase_valueSignals[ref.description] ||= {}
      hash[:numberOfValueSubscribers] ||= 0
      valueSubject = hash[:valueSubject] ||= RACReplaySubject.replaySubjectWithCapacity(1)
      if hash[:numberOfValueSubscribers] == 0
        hash[:valueHandler] = ref.observeEventType(FEventTypeValue, withBlock:->(curr) {
          RECURSIVE_LOCK.lock
          valueSubject.sendNext(curr)
          RECURSIVE_LOCK.unlock
        }, withCancelBlock:->(err) {
          RECURSIVE_LOCK.lock
          valueSubject.sendError(err)
          RECURSIVE_LOCK.unlock
        })
      end
      hash[:numberOfValueSubscribers] += 1
      valueSubjectDisposable = valueSubject.subscribe(subscriber)
      RECURSIVE_LOCK.unlock
      RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        valueSubjectDisposable.dispose
        hash[:numberOfValueSubscribers] -= 1
        if hash[:numberOfValueSubscribers] == 0
          if valueHandler = hash[:valueHandler]
            ref.removeObserverWithHandle(valueHandler)
          else
            p "MISSING EXPECTED valueHandler!"
          end
          hash[:valueHandler] = nil
          hash[:valueSubject] = nil
        end
        RECURSIVE_LOCK.unlock
      })
    })
  end

  # ChildAdded sends [ curr, prev ]
  def rac_addedSignal
    self.class.rac_addedSignal(self)
  end
  def self.rac_addedSignal(ref)
    RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = ref.observeEventType(FEventTypeChildAdded, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_addedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("rac_addedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        ref.removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    })
  end

  # ChildMoved sends [ curr, prev ]
  def rac_movedSignal
    self.class.rac_movedSignal(self)
  end
  def self.rac_movedSignal(ref)
    RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = ref.observeEventType(FEventTypeChildMoved, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_movedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("rac_movedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        ref.removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    })
  end

  # ChildChanged sends [ curr, prev ]
  def rac_changedSignal
    self.class.rac_changedSignal(self)
  end
  def self.rac_changedSignal(ref)
    RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = ref.observeEventType(FEventTypeChildChanged, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_changedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("rac_changedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        ref.removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    })
  end

  # ChildRemoved sends curr
  def rac_removedSignal
    self.class.rac_removedSignal(self)
  end
  def self.rac_removedSignal(ref)
    RACSignal.createSignal(-> (subscriber) {
      RECURSIVE_LOCK.lock
      handler = ref.observeEventType(FEventTypeChildRemoved, withBlock:->(curr) {
        subscriber.sendNext(curr)
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_removedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        # NSLog("rac_removedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        ref.removeObserverWithHandle(handler)
        RECURSIVE_LOCK.unlock
      })
      RECURSIVE_LOCK.unlock
      dis
    })
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
