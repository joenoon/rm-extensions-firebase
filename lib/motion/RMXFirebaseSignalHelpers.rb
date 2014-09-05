module RMXFirebaseSignalHelpers

  # completes with `self` once, when or if the model is loaded.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # retains `self` and the sender until complete
  # returns a RACDisposable
  def once(scheduler=nil, &block)
    @readySignal
    .take(1)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(->(v) {
      block.call(self)
    })
  end

  # completes with `self` any time the model is loaded or changed.
  # does not retain `self` or the sender.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # returns a RACDisposable
  def always(scheduler=nil, &block)
    sblock = RMX.safe_block(block)
    @readySignal
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(RMX.safe_lambda do |b|
      sblock.call(self)
    end)
  end

  # completes with `self` every time the model changes.
  # does not retain `self` or the sender.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # returns a RACDisposable
  def changed(scheduler=nil, &block)
    sblock = RMX.safe_block(block)
    @readySignal
    .skip(1)
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(RMX.safe_lambda do |b|
      sblock.call(self)
    end)
  end

end
