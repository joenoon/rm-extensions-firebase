class FQuery

  def [](*names)
    if names.length == 0
      childByAutoId
    else
      childByAppendingPath(names.join('/'))
    end
  end

  def limited(limit)
    queryLimitedToNumberOfChildren(limit)
  end

  def starting_at(priority, child_name=nil)
    if child_name
      queryStartingAtPriority(priority, andChildName:child_name)
    else
      queryStartingAtPriority(priority)
    end
  end

  def ending_at(priority, child_name=nil)
    if child_name
      queryEndingAtPriority(priority, andChildName:child_name)
    else
      queryEndingAtPriority(priority)
    end
  end

  def ref_description
    "https://#{repo.repoInfo.host}#{path.toString}##{queryParams.queryIdentifier}"
  end

  # Value sends curr
  def rac_valueSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeValue, withBlock:->(curr) {
        subscriber.sendNext(curr)
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      })
    })
    .subscribeOn(RMXFirebase.scheduler)
  end

  # ChildAdded sends [ curr, prev ]
  def rac_addedSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeChildAdded, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      })
    })
    .subscribeOn(RMXFirebase.scheduler)
  end

  # ChildMoved sends [ curr, prev ]
  def rac_movedSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeChildMoved, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      })
    })
    .subscribeOn(RMXFirebase.scheduler)
  end

  # ChildChanged sends [ curr, prev ]
  def rac_changedSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeChildChanged, andPreviousSiblingNameWithBlock:->(curr, prev) {
        subscriber.sendNext([ curr, prev ])
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      })
    })
    .subscribeOn(RMXFirebase.scheduler)
  end

  # ChildRemoved sends curr
  def rac_removedSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeChildRemoved, withBlock:->(curr) {
        subscriber.sendNext(curr)
      }, withCancelBlock:->(err) {
        subscriber.sendError(err)
      })
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      })
    })
    .subscribeOn(RMXFirebase.scheduler)
  end

  # will sendNext with authData or error
  def rac_authWithCredentialSignal(firebase_auth)
    RACSignal.createSignal(->(subscriber) {
      authWithCredential(firebase_auth, withCompletionBlock:->(error, authData) {
        if error
          subscriber.sendError(error)
        else
          subscriber.sendNext(authData)
        end
      }, withCancelBlock:->(error) {
        subscriber.sendError(error)
      })
      nil
    })
    .subscribeOn(RMXFirebase.scheduler)
  end

end
