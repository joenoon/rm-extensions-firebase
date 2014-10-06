class RMXFirebaseLiveshot

  include RMXFirebaseSignalHelpers

  SNAP_KEY = "snap"
  REF_KEY = "ref"

  attr_accessor :snap, :ref

  # readySignal will next true when:
  #   it is ready
  #   it becomes ready
  #   it changes
  #
  attr_reader :readySignal

  # changedSignal will next true when:
  #   it changes
  attr_reader :changedSignal

  def initialize(_ref)
    RMX.log_dealloc(self)

    @ref = _ref

    @readySignal = RACReplaySubject.replaySubjectWithCapacity(1)
    @changedSignal = RMX(self).racObserve("snap").ignore(nil).mapReplace(true)
    @changedSignal.subscribe(@readySignal)

    RMX(self).rac("snap").signal = RMX(self).racObserve("ref")
    .map(->(_r) { _r.rac_valueSignal.catchTo(RACSignal.never) }.weak!)
    .switchToLatest


  end

  def ref_description
    if r = @ref
      r.ref_description
    end
  end

  def loaded?
    !!snap
  end

  def ready?
    loaded? && hasValue?
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
    valueForKeyPath(keypath)
  end

  def valueForKey(key)
    case key
    when SNAP_KEY
      snap
    when REF_KEY
      ref
    else
      if s = snap
        s.valueForKey(key)
      end
    end
  end

  def valueForUndefinedKey(key)
    nil
  end

  def children
    if s = snap
      s.children
    else
      []
    end
  end

  def childrenArray
    children.allObjects
  end

end
