class RMXFirebaseLiveshot

  RECURSIVE_LOCK = NSRecursiveLock.new
  
  include RMXFirebaseSignalHelpers

  # readySignal will next true when:
  #   it is ready
  #   it becomes ready
  #   it changes
  #
  attr_reader :readySignal

  # changedSignal will next true when:
  #   it changes
  attr_reader :changedSignal

  def initialize(ref)
    RMX.log_dealloc(self)

    @readySignal = RACReplaySubject.replaySubjectWithCapacity(1)
    @changedSignal = RACSubject.subject
    @refSignal = RACSubject.subject

    @refSignal.switchToLatest
    .takeUntil(rac_willDeallocSignal)
    .subscribeNext(RMX.safe_lambda do |snap|
      self.snap = snap
    end)
    self.ref = ref
  end

  def ref=(ref)
    RECURSIVE_LOCK.lock
    @ref = ref
    RECURSIVE_LOCK.unlock
    @refSignal.sendNext(ref.rac_valueSignal)
  end

  # ref this Liveshot is observing
  def ref
    RECURSIVE_LOCK.lock
    res = @ref
    RECURSIVE_LOCK.unlock
    res
  end

  def loaded?
    !!snap
  end

  def snap=(snap)
    RECURSIVE_LOCK.lock
    @snap = snap
    RECURSIVE_LOCK.unlock
    @readySignal.sendNext(true)
    @changedSignal.sendNext(true)
    snap
  end

  def snap
    RECURSIVE_LOCK.lock
    res = @snap
    RECURSIVE_LOCK.unlock
    res
  end

  def name
    if s = snap
      s.name
    end
  end

  def value
    if s = snap
      s.value
    end
  end

  def priority
    if s = snap
      s.priority
    end
  end

  def hasValue?
    !value.nil?
  end

  def attr(keypath)
    if s = snap
      s.valueForKeyPath(keypath)
    end
  end

  def childrenArray
    if s = snap
      s.children.each.map { |x| x }
    else
      []
    end
  end

end
