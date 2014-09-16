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
    sblock = block.rmx_weak!
    @readySignal
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(->(b) {
      sblock.call(self)
    }.rmx_weak!)
  end

  # completes with `self` every time the model changes.
  # does not retain `self` or the sender.
  # takes optional RACScheduler (mainThreadScheduler is default).
  # returns a RACDisposable
  def changed(scheduler=nil, &block)
    sblock = block.rmx_weak!
    @changedSignal
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(->(b) {
      sblock.call(self)
    }.rmx_weak!)
  end

end
