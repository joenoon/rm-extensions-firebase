# to get models to show up in Instruments, for some reason need to < UIResponder 
class RMXFirebaseModel

  RECURSIVE_LOCK = NSRecursiveLock.new
  
  include RMXCommonMethods
  include RMXFirebaseSignalHelpers
  
  def self.get(opts=nil)
    new(opts)
  end

  def self.property(name)
    attr_reader name
  end

  property :_root

  attr_reader :opts

  # readySignal will next true when:
  #   it is ready
  #   it becomes ready
  #   it changes
  #
  attr_reader :readySignal

  # changedSignal will next true when:
  #   it changes
  attr_reader :changedSignal

  def initialize(opts=nil)
    RMX.log_dealloc(self)
    @opts = opts
    @checkSubject = RACSubject.subject
    self.rac_liftSelector('makeReady', withSignalsFromArray:[@checkSubject.switchToLatest])
    @readySignal = RACReplaySubject.replaySubjectWithCapacity(1)
    @changedSignal = RACSubject.subject
    @deps = {}
    setup
  end

  def makeReady(*args)
    # p "makeReady!!!!", fullValue
    RECURSIVE_LOCK.lock
    @loaded = true
    RECURSIVE_LOCK.unlock
    @readySignal.sendNext(true)
    @changedSignal.sendNext(true)
  end

  def loaded?
    RECURSIVE_LOCK.lock
    res = !!@loaded
    RECURSIVE_LOCK.unlock
    res
  end

  def check
    deps = @deps.values.map { |x| x[:signal] }
    @checkSubject.sendNext(RACSignal.combineLatest(deps))
  end

  def root(object, opts={}, &block)
    depend(:_root, object, opts, &block)
  end

  def depend(name, object, opts={}, &block)
    sblock = block ? RMX.safe_block(block) : nil
    # RECURSIVE_LOCK.lock
    undepend(name)
    instance_variable_set("@#{name}", object)
    weak_object = RMXWeakHolder.new(object)
    @deps[name] = {
      :signal => object.readySignal
    }
    @deps[name][:disposable] = @deps[name][:signal]
    .takeUntil(object.rac_willDeallocSignal)
    .subscribeNext(RMX.safe_lambda do |v|
      RECURSIVE_LOCK.lock
      if sblock and obj = weak_object.value
        sblock.call(obj)
      end
      # p "check after #{name}"
      check
      RECURSIVE_LOCK.unlock
    end)
    # RECURSIVE_LOCK.unlock
  end

  def depend_if(name, cond, opts={}, &block)
    if cond
      existing = instance_variable_get("@#{name}")
      if !existing || existing.opts != cond
        if res = block.call(cond)
          depend(name, res, opts) do |r|
            if opts[:then]
              opts[:then].call(r)
            end
          end
        end
      end
    else
      undepend(name)
    end
  end

  def undepend(name)
    # RECURSIVE_LOCK.lock
    if dep = @deps[name]
      if dis = dep[:disposable]
        dis.dispose
      end
      @deps.delete(name)
    end
    instance_variable_set("@#{name}", nil)
    # RECURSIVE_LOCK.unlock
  end

  def attr(keypath)
    _root.attr(keypath)
  end

  def hasValue?
    _root.hasValue?
  end

  def value
    _root.value
  end

  def fullValue
    RECURSIVE_LOCK.lock
    res = @deps.keys.inject({}) do |ret, k|
      ret[k] = send(k).value
      ret
    end
    RECURSIVE_LOCK.unlock
    res
  end

  def setup
    raise "unimplemented: #{className}#setup"
  end

  def hash
    [ className, @opts ].hash
  end

  def isEqual(other)
    hash == other.hash
  end

  alias_method :==, :isEqual
  alias_method :eql?, :isEqual

end
