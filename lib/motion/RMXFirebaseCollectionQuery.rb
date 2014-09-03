class RMXFirebaseCollectionQuery < RMXFirebaseModelQuery

  attr_reader :cancel_error

  def transformed_signal(queue=nil, _pager=nil)
    RACSignal.combineLatest([
      rac_valueSignal,
      _pager && _pager.rac_valueSignal || nil
    ].compact)
    .flattenMap(->(tuple) {
      RECURSIVE_LOCK.lock
      snaps = tuple[0].root.childrenArray
      RECURSIVE_LOCK.unlock
      pager = tuple[1]

      range = pager && pager.range
      order = pager && pager.order

      snaps = order == :desc ? snaps.reverse : snaps
      snaps = range ? snaps[range] : snaps
      items = snaps.map { |snap| klass.transform(snap) }

      RACSignal.combineLatestOrEmptyToArray(items.map(&:rac_valueSignal)).take(1)
    })
  end

  # completes with `models` once, when the collection is changed.
  # takes optional pager.
  # retains `self` and the sender until complete
  def once_models(queue=nil, pager=nil, &block)
    transformed_signal(queue, pager)
    .take(1)
    .deliverOn(RACScheduler.mainThreadScheduler)
    .subscribeNext(->(v) {
      block.call(v)
    })
  end

  # completes with `models` immediately if changed, and every time the collection changes.
  # does not retain `self` or the sender.
  # takes optional pager.
  # returns an "unbinder" that can be called to stop listening.
  def always_models(queue=nil, pager=nil, &block)
    sblock = RMX.safe_lambda(block)
    transformed_signal(queue, pager)
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RACScheduler.mainThreadScheduler)
    .subscribeNext(sblock)
  end

  # completes with `models` every time the collection changes.
  # does not retain `self` or the sender.
  # takes optional pager.
  # returns an "unbinder" that can be called to stop listening.
  def changed_models(queue=nil, pager=nil, &block)
    sblock = RMX.safe_lambda(block)
    transformed_signal(queue, pager)
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RACScheduler.mainThreadScheduler)
    .subscribeNext(sblock)
  end

  # completes with `model` every time the collection :added_model fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def added_model(queue=nil, &block)
    sblock = RMX.safe_lambda(block)
    ref.rac_valueSignal
    .then(ref.rac_addedSignal)
    .flattenMap(->(tuple) {
      item = klass.transform(tuple[0])
      RACSignal.combineLatest([
        RACSignal.return(item),
        item.rac_valueSignal
      ]).take(1)
    })
    .flattenMap(->(tuple) {
      RACSignal.return(tuple[0])
    })
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RACScheduler.mainThreadScheduler)
    .subscribeNext(sblock)
  end

  # completes with `model` every time the collection :removed fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def removed_model(queue=nil, &block)
    sblock = RMX.safe_lambda(block)
    ref.rac_removedSignal
    .flattenMap(->(tuple) {
      item = klass.transform(tuple[0])
      RACSignal.return(item)
    })
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RACScheduler.mainThreadScheduler)
    .subscribeNext(sblock)
  end

  def ref
    RECURSIVE_LOCK.lock
    res = @opts
    RECURSIVE_LOCK.unlock
    res
  end

end
