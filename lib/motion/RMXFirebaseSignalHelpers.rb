module RMXFirebaseSignalHelpers

  # always
  def weakAlwaysSignal
    readySignal.takeUntil(rac_willDeallocSignal).map(->(x) { self }.weak!)
  end

  def weakAlwaysMainSignal
    weakAlwaysSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  def strongAlwaysSignal
    readySignal.mapReplace(self)
  end

  def strongAlwaysMainSignal
    strongAlwaysSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  # once
  def weakOnceSignal
    weakAlwaysSignal.take(1)
  end

  def weakOnceMainSignal
    weakOnceSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  def strongOnceSignal
    strongAlwaysSignal.take(1)
  end

  def strongOnceMainSignal
    strongOnceSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  # changed
  def weakChangedSignal
    changedSignal.takeUntil(rac_willDeallocSignal).map(->(x) { self }.weak!)
  end

  def weakChangedMainSignal
    weakChangedSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  def strongChangedSignal
    changedSignal.mapReplace(self)
  end

  def strongChangedMainSignal
    strongChangedSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  # changed once
  def weakOnceChangedSignal
    weakChangedSignal.take(1)
  end

  def weakOnceChangedMainSignal
    weakOnceChangedSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  def strongOnceChangedSignal
    strongChangedSignal.take(1)
  end

  def strongOnceChangedMainSignal
    strongOnceChangedSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

end
