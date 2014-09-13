class FQuery

  LOCK = NSLock.new

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
    "https://#{repo.repoInfo.host}#{path.toString}##{queryParams.queryIdentifier}"
  end

  def liveshot
    RMXFirebaseLiveshot.new(self)
  end

  # Value sends curr
  def rac_valueSignal
    self.class.rac_valueSignal(self)
  end
  def self.rac_valueSignal(ref)
    RACSignal.createSignal(->(subscriber) {
      LOCK.lock
      hash = $firebase_valueSignals[ref.description] ||= {}
      hash[:numberOfValueSubscribers] ||= 0
      valueSubject = hash[:valueSubject] ||= RACReplaySubject.replaySubjectWithCapacity(1)
      if hash[:numberOfValueSubscribers] == 0
        hash[:valueHandler] = ref.observeEventType(FEventTypeValue, withBlock:->(curr) {
          LOCK.lock
          valueSubject.sendNext(curr)
          LOCK.unlock
        }, withCancelBlock:->(err) {
          LOCK.lock
          valueSubject.sendError(err)
          LOCK.unlock
        })
        # ref.p "observeEventType", hash[:valueHandler]
      end
      hash[:numberOfValueSubscribers] += 1
      valueSubjectDisposable = valueSubject.subscribe(subscriber)
      LOCK.unlock
      RACDisposable.disposableWithBlock(-> {
        LOCK.lock
        valueSubjectDisposable.dispose
        hash[:numberOfValueSubscribers] -= 1
        if hash[:numberOfValueSubscribers] == 0
          if valueHandler = hash[:valueHandler]
            ref.removeObserverWithHandle(valueHandler)
            # ref.p "removeObserverWithHandle", valueHandler
          else
            NSLog("MISSING EXPECTED valueHandler!")
          end
          hash[:valueHandler] = nil
          hash[:valueSubject] = nil
        end
        LOCK.unlock
      })
    }).subscribeOn(RMXFirebase.scheduler)
  end

  # ChildAdded sends [ curr, prev ]
  def rac_addedSignal
    self.class.rac_addedSignal(self)
  end
  def self.rac_addedSignal(ref)
    RACSignal.createSignal(-> (subscriber) {
      LOCK.lock
      handler = ref.observeEventType(FEventTypeChildAdded, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_addedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        LOCK.lock
        # NSLog("rac_addedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        ref.removeObserverWithHandle(handler)
        LOCK.unlock
      })
      LOCK.unlock
      dis
    }).subscribeOn(RMXFirebase.scheduler)
  end

  # ChildMoved sends [ curr, prev ]
  def rac_movedSignal
    self.class.rac_movedSignal(self)
  end
  def self.rac_movedSignal(ref)
    RACSignal.createSignal(-> (subscriber) {
      LOCK.lock
      handler = ref.observeEventType(FEventTypeChildMoved, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_movedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        LOCK.lock
        # NSLog("rac_movedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        ref.removeObserverWithHandle(handler)
        LOCK.unlock
      })
      LOCK.unlock
      dis
    }).subscribeOn(RMXFirebase.scheduler)
  end

  # ChildChanged sends [ curr, prev ]
  def rac_changedSignal
    self.class.rac_changedSignal(self)
  end
  def self.rac_changedSignal(ref)
    RACSignal.createSignal(-> (subscriber) {
      LOCK.lock
      handler = ref.observeEventType(FEventTypeChildChanged, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_changedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        LOCK.lock
        # NSLog("rac_changedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        ref.removeObserverWithHandle(handler)
        LOCK.unlock
      })
      LOCK.unlock
      dis
    }).subscribeOn(RMXFirebase.scheduler)
  end

  # ChildRemoved sends curr
  def rac_removedSignal
    self.class.rac_removedSignal(self)
  end
  def self.rac_removedSignal(ref)
    RACSignal.createSignal(-> (subscriber) {
      LOCK.lock
      handler = ref.observeEventType(FEventTypeChildRemoved, withBlock:->(curr) {
        subscriber.sendNext(curr)
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      # NSLog("rac_removedSignal #{description} handler: #{handler}")

      dis = RACDisposable.disposableWithBlock(-> {
        LOCK.lock
        # NSLog("rac_removedSignal disposableWithBlock removeObserverWithHandle(#{handler})")
        ref.removeObserverWithHandle(handler)
        LOCK.unlock
      })
      LOCK.unlock
      dis
    }).subscribeOn(RMXFirebase.scheduler)
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
