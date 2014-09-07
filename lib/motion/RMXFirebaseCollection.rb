class RMXFirebaseCollection < RMXFirebaseLiveshot

  attr_accessor :order

  # public, override required
  def transform(snap)
    raise "#{className}#transform(snap): override to return a RMXFirebaseModel based on the snap"
  end

  def self.get(ref)
    new(ref)
  end

  def modelsSignal
    RACSignal.createSignal(->(subscriber) {
      RECURSIVE_LOCK.lock
      hash = @modelsSignalInfo
      hash[:numberOfSubscribers] ||= 0
      subject = hash[:subject] ||= RACReplaySubject.replaySubjectWithCapacity(1)
      if hash[:numberOfSubscribers] == 0
        hash[:handler] = @readySignal
        .subscribeOn(RACScheduler.scheduler)
        .takeUntil(rac_willDeallocSignal)
        .subscribeNext(RMX.safe_lambda do |x|
          snaps = order == :desc ? childrenArray.reverse : childrenArray
          items = snaps.map { |s| store_transform(s) } 
          signals = items.map(&:readySignal)
          RACSignal.combineLatestOrEmpty(signals)
          .subscribeOn(RACScheduler.scheduler)
          .take(1)
          .flattenMap(->(tuple) {
            RACSignal.return(tuple.allObjects)
          })
          .subscribeNext(RMX.safe_lambda do |bools|
            subject.sendNext(items)
          end)
        end)
        # ref.p "observeEventType", hash[:valueHandler]
      end
      hash[:numberOfSubscribers] += 1
      subjectDisposable = subject.subscribe(subscriber)
      RECURSIVE_LOCK.unlock
      RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        subjectDisposable.dispose
        hash[:numberOfSubscribers] -= 1
        if hash[:numberOfSubscribers] == 0
          if handler = hash[:handler]
            handler.dispose
            # ref.p "removeObserverWithHandle", valueHandler
          else
            p "MISSING EXPECTED valueHandler!"
          end
          hash[:handler] = nil
          hash[:subject] = nil
        end
        RECURSIVE_LOCK.unlock
      })
    })
  end

  def addedSignal
    RACSignal.createSignal(->(subscriber) {
      disposable = @readySignal
      .then(ref.rac_addedSignal)
      .subscribeNext(RMX.safe_lambda do |pair|
        subscriber.sendNext([ store_transform(pair[0]), pair[1] ])
      end)
      RACDisposable.disposableWithBlock(-> {
        disposable.dispose
      })
    })
  end

  def removedSignal
    RACSignal.createSignal(->(subscriber) {
      disposable = @readySignal
      .then(ref.rac_removedSignal)
      .subscribeNext(RMX.safe_lambda do |s|
        subscriber.sendNext(s)
      end)
      RACDisposable.disposableWithBlock(-> {
        disposable.dispose
      })
    })
  end

  def movedSignal
    RACSignal.createSignal(->(subscriber) {
      disposable = @readySignal
      .then(ref.rac_movedSignal)
      .subscribeNext(RMX.safe_lambda do |pair|
        subscriber.sendNext([ store_transform(pair[0]), pair[1] ])
      end)
      RACDisposable.disposableWithBlock(-> {
        disposable.dispose
      })
    })
  end

  def initialize(ref)
    super
    @modelsSignalInfo = {}
    @models = {}
  end

  def store_transform(snap)
    @models[snap.name] ||= transform(snap)
  end

  # completes with `models` once, when the collection is changed.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # retains `self` and the sender until complete
  # returns a RACDisposable
  def once_models(scheduler=nil, &block)
    modelsSignal
    .subscribeOn(RACScheduler.scheduler)
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
    modelsSignal
    .subscribeOn(RACScheduler.scheduler)
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
    modelsSignal
    .subscribeOn(RACScheduler.scheduler)
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
    addedSignal
    .subscribeOn(RACScheduler.scheduler)
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
    removedSignal
    .subscribeOn(RACScheduler.scheduler)
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(sblock)
  end

  # adjust the current Firebase ref's limit by an increment number
  def limitIncrBy(num)
    if r = ref
      if l = r.queryParams && r.queryParams.queryObject["l"]
        new_limit = l.to_i + num
        new_limit = 0 if new_limit < 0
        new_ref = r.limited(new_limit)
        self.ref = new_ref
      else
        NSLog("#{className}#limitIncrBy WARNING: tried to increament a non-existent limit for #{r.description}")
      end
    end
  end

  # adjust the current Firebase ref's limit to an exact number
  def limitTo(num)
    if r = ref
      new_ref = r.limited(num)
      self.ref = new_ref
    end
  end

  # order will affect future passes through modelsSignal, so set it before
  # using modelsSignal (i.e. always_models, changed_models, once_models)
  def order=(order)
    RECURSIVE_LOCK.lock
    @order = order
    RECURSIVE_LOCK.unlock
  end

  def order
    RECURSIVE_LOCK.lock
    res = @order
    RECURSIVE_LOCK.unlock
    res
  end

end
