class RMXFirebaseCollection < RMXFirebaseLiveshot

  attr_accessor :order

  # public, override required
  def transform(snap)
    raise "#{className}#transform(snap): override to return a RMXFirebaseModel based on the snap"
  end

  def self.get(ref)
    new(ref)
  end

  def initialize(ref)
    super
    @models = {}

    @modelsSignal = RACReplaySubject.replaySubjectWithCapacity(1)
    @addedSignal = RACSubject.subject
    @removedSignal = RACSubject.subject
    @movedSignal = RACSubject.subject

    @readySignal
    .takeUntil(rac_willDeallocSignal)
    .subscribeNext(RMX.safe_lambda do |x|
      items = childrenArray.map { |s| store_transform(s) }
      RACSignal.combineLatestOrEmptyToArray(items.map(&:readySignal))
      .take(1)
      .subscribeNext(RMX.safe_lambda do |bools|
        @modelsSignal.sendNext(items)
      end)
    end)

    @readySignal
    .then(ref.rac_addedSignal)
    .takeUntil(rac_willDeallocSignal)
    .subscribeNext(RMX.safe_lambda do |pair|
      @addedSignal.sendNext([ store_transform(pair[0]), pair[1] ])
    end)

    @readySignal
    .then(ref.rac_removedSignal)
    .takeUntil(rac_willDeallocSignal)
    .subscribeNext(RMX.safe_lambda do |s|
      @removedSignal.sendNext(s)
    end)

    @readySignal
    .then(ref.rac_movedSignal)
    .takeUntil(rac_willDeallocSignal)
    .subscribeNext(RMX.safe_lambda do |pair|
      @movedSignal.sendNext([ store_transform(pair[0]), pair[1] ])
    end)

  end

  def store_transform(snap)
    @models[snap.name] ||= transform(snap)
  end

  # completes with `models` once, when the collection is changed.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # retains `self` and the sender until complete
  # returns a RACDisposable
  def once_models(scheduler=nil, &block)
    @modelsSignal
    .take(1)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(->(v) {
      block.call(v)
    })
  end

  # completes with `models` immediately if changed, and every time the collection changes.
  # does not retain `self` or the sender.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # returns a RACDisposable
  def always_models(scheduler=nil, &block)
    sblock = RMX.safe_lambda(block)
    @modelsSignal
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(sblock)
  end

  # completes with `models` every time the collection changes.
  # does not retain `self` or the sender.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # returns a RACDisposable
  def changed_models(scheduler=nil, &block)
    sblock = RMX.safe_lambda(block)
    @modelsSignal
    .skip(1)
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(sblock)
  end

  # completes with `model` every time the collection :added_model fires.
  # does not retain `self` or the sender.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # returns a RACDisposable
  def added_model(scheduler=nil, &block)
    sblock = RMX.safe_lambda(block)
    @addedSignal
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(sblock)
  end

  # completes with `model` every time the collection :removed fires.
  # does not retain `self` or the sender.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # returns a RACDisposable
  def removed_model(scheduler=nil, &block)
    sblock = RMX.safe_lambda(block)
    @removedSignal
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(sblock)
  end

end
