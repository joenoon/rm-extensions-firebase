class FQuery

  def [](*names)
    if names.length == 0
      childByAutoId
    else
      childByAppendingPath(names.join('/'))
    end
  end

  def freshRef
    Firebase.alloc.initWithUrl("https://#{repo.repoInfo.host}#{path.toString}")
  end

  def ref_description
    "https://#{repo.repoInfo.host}#{path.toString}##{queryParams.queryIdentifier}"
  end

  # type FEventTypeValue
  # nexts FDataSnapshot *snapshot or sends error
  def rac_valueSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeValue, withBlock:->(curr) {
        subscriber.sendNext(curr)
      }.weak!, withCancelBlock:->(err) {
        subscriber.sendError(err)
      }.weak!)
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      }.weak!)
    })
    .takeUntil(rac_willDeallocSignal)
  end

  # type FEventTypeChildAdded
  # nexts RACTuplePack(FDataSnapshot *snapshot, NSString *prevKey) or sends error
  def rac_addedSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeChildAdded, andPreviousSiblingKeyWithBlock:->(curr, prev) {
        subscriber.sendNext(RACTuple.tupleWithObjectsFromArray([ curr, prev ]))
      }.weak!, withCancelBlock:->(err) {
        subscriber.sendError(err)
      }.weak!)
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      }.weak!)
    })
    .takeUntil(rac_willDeallocSignal)
  end

  # type FEventTypeChildMoved
  # nexts RACTuplePack(FDataSnapshot *snapshot, NSString *prevKey) or sends error
  def rac_movedSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeChildMoved, andPreviousSiblingKeyWithBlock:->(curr, prev) {
        subscriber.sendNext(RACTuple.tupleWithObjectsFromArray([ curr, prev ]))
      }.weak!, withCancelBlock:->(err) {
        subscriber.sendError(err)
      }.weak!)
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      }.weak!)
    })
    .takeUntil(rac_willDeallocSignal)
  end

  # type FEventTypeChildChanged
  # nexts RACTuplePack(FDataSnapshot *snapshot, NSString *prevKey) or sends error
  def rac_changedSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeChildChanged, andPreviousSiblingKeyWithBlock:->(curr, prev) {
        subscriber.sendNext(RACTuple.tupleWithObjectsFromArray([ curr, prev ]))
      }.weak!, withCancelBlock:->(err) {
        subscriber.sendError(err)
      }.weak!)
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      }.weak!)
    })
    .takeUntil(rac_willDeallocSignal)
  end

  # type FEventTypeChildRemoved
  # nexts FDataSnapshot *snapshot or sends error
  def rac_removedSignal
    RACSignal.createSignal(->(subscriber) {
      handler = observeEventType(FEventTypeChildRemoved, withBlock:->(curr) {
        subscriber.sendNext(curr)
      }.weak!, withCancelBlock:->(err) {
        subscriber.sendError(err)
      }.weak!)
      RACDisposable.disposableWithBlock(-> {
        removeObserverWithHandle(handler)
      }.weak!)
    })
    .takeUntil(rac_willDeallocSignal)
  end

end
