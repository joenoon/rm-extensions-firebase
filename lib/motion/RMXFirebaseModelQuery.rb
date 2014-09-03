class RMXFirebaseModelQuery

  RECURSIVE_LOCK = NSRecursiveLock.new

  Dispatch.once do
    $rmx_firebase_model_valueSignals = {}
  end

  attr_accessor :klass, :opts

  def initialize(klass, opts=nil)
    @klass = klass
    @opts = opts
  end

  # Value sends curr
  def rac_valueSignal
    self.class.rac_valueSignal(self)
  end
  def self.rac_valueSignal(ref)
    ref_klass = ref.klass
    ref_opts = ref.opts
    RACSignal.createSignal(->(subscriber) {
      RECURSIVE_LOCK.lock
      hash = $rmx_firebase_model_valueSignals[[ref_klass, ref_opts]] ||= {}
      hash[:numberOfValueSubscribers] ||= 0
      valueSubject = hash[:valueSubject] ||= RACReplaySubject.replaySubjectWithCapacity(1)
      if hash[:numberOfValueSubscribers] == 0
        hash[:valueHandler] = ref_klass.setup(ref_opts)
        .subscribeNext(->(components) {
          valueSubject.sendNext(ref_klass.new(components.merge(:opts => ref_opts)))
        }, error:->(err) {
          valueSubject.sendError(err)
        })
      end
      hash[:numberOfValueSubscribers] += 1
      valueSubjectDisposable = valueSubject.subscribe(subscriber)
      RECURSIVE_LOCK.unlock
      RACDisposable.disposableWithBlock(-> {
        RECURSIVE_LOCK.lock
        valueSubjectDisposable.dispose
        hash[:numberOfValueSubscribers] -= 1
        if hash[:numberOfValueSubscribers] == 0
          if valueHandler = hash[:valueHandler]
            valueHandler.dispose
          else
            p "MISSING EXPECTED valueHandler!"
          end
          hash[:valueHandler] = nil
          hash[:valueSubject] = nil
        end
        RECURSIVE_LOCK.unlock
      })
    })
  end

  def always(queue=nil, &block)
    sblock = RMX.safe_lambda(block)
    rac_valueSignal
    .takeUntil(block.owner.rac_willDeallocSignal)
    .deliverOn(RACScheduler.mainThreadScheduler)
    .subscribeNext(sblock)
  end

  def changed(queue=nil, &block)
    sblock = RMX.safe_lambda(block)
    rac_valueSignal
    .takeUntil(block.owner.rac_willDeallocSignal)
    .skip(1)
    .deliverOn(RACScheduler.mainThreadScheduler)
    .subscribeNext(sblock)
  end

  def once(queue=nil, &block)
    rac_valueSignal
    .take(1)
    .deliverOn(RACScheduler.mainThreadScheduler)
    .subscribeNext(->(val) {
      block.call(val)
    })
  end

end
