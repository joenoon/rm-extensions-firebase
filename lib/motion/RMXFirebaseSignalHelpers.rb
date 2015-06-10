module RMXFirebaseSignalHelpers

  # always
  def weakAlwaysSignal
    readySignal.takeUntil(rac_willDeallocSignal).map(->(x) { self }.weak!)
  end

  def weakAlwaysMainSignal
    weakAlwaysSignal.deliverOnMainThread
  end

  def strongAlwaysSignal
    readySignal.mapReplace(self)
  end

  def strongAlwaysMainSignal
    strongAlwaysSignal.deliverOnMainThread
  end

  # once
  def weakOnceSignal
    weakAlwaysSignal.take(1)
  end

  def weakOnceMainSignal
    weakOnceSignal.deliverOnMainThread
  end

  def strongOnceSignal
    strongAlwaysSignal.take(1)
  end

  def strongOnceMainSignal
    strongOnceSignal.deliverOnMainThread
  end

  # changed
  def weakChangedSignal
    changedSignal.takeUntil(rac_willDeallocSignal).map(->(x) { self }.weak!)
  end

  def weakChangedMainSignal
    weakChangedSignal.deliverOnMainThread
  end

  def strongChangedSignal
    changedSignal.mapReplace(self)
  end

  def strongChangedMainSignal
    strongChangedSignal.deliverOnMainThread
  end

  # changed once
  def weakOnceChangedSignal
    weakChangedSignal.take(1)
  end

  def weakOnceChangedMainSignal
    weakOnceChangedSignal.deliverOnMainThread
  end

  def strongOnceChangedSignal
    strongChangedSignal.take(1)
  end

  def strongOnceChangedMainSignal
    strongOnceChangedSignal.deliverOnMainThread
  end

end
