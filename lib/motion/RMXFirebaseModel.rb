# to get models to show up in Instruments, for some reason need to < UIResponder 
class RMXFirebaseModel

  include RMXCommonMethods

  include RMXFirebaseSignalHelpers
  
  def self.get(opts=nil)
    new(opts)
  end

  def self.property(name)
    attr_accessor name
  end

  property :root

  attr_accessor :loaded

  attr_reader :opts

  # readySignal will next true when:
  #   it is ready
  #   it becomes ready
  #   it changes
  #
  attr_reader :readySignal

  # changedSignal will next true when:
  #   it changes
  def changedSignal
    @readySignal.skip(1)
  end

  def initialize(opts=nil)
    RMX.log_dealloc(self)
    @deps = {}
    @opts = opts
    @loaded = false

    @readySignal = RACReplaySubject.replaySubjectWithCapacity(1)

    setup

    names = []
    sigs = []
    @deps.each_pair do |name, sig|
      names << name
      sigs << sig
    end

    RACSignal.combineLatest(sigs)
    .takeUntil(rac_willDeallocSignal)#.doNext(->(x) { NSLog("(#{rmx_object_desc}) READY") }.weak!)
    .subscribeNext(->(tuple) {
      names.each_with_index do |name, i|
        if val = tuple[i]
          setValue(val, forKey:name)
        end
      end
      setValue(true, forKey:"loaded")
      @readySignal.sendNext(true)
      # p "READY"
    }.weak!)

  end

  def depend(name, opts)
    the_sig = opts[:signal] || begin
      model = opts[:model]
      parts = opts[:keypath].split(".")
      dep = parts.shift
      keypath = parts.join(".")
      @deps[dep]#.setNameWithFormat("(#{rmx_object_desc}) #{name} check because of #{dep}").logAll
      .map(->(x) {
        # p "here"
        x.valueForKeyPath(keypath)
      }.weak!)#.setNameWithFormat("(#{rmx_object_desc}) #{name} opts for keypath #{keypath}").logAll
      .distinctUntilChanged
      .map(->(opts) {
        if opts
          # p "depend", name, "send strongSingal", "model", model, "opts", opts
          model.get(opts).strongAlwaysSignal
        else
          # p "depend", name, "send nilSignal"
          RACSignal.return(nil)
        end
      }.weak!)
      .switchToLatest#.setNameWithFormat("(#{rmx_object_desc}) #{name} result for keypath #{keypath}").logAll
      .takeUntil(rac_willDeallocSignal)
      .replayLast
    end
    @deps[name.to_s] = the_sig
    nil
  end

  def attr(keypath)
    root.attr(keypath)
  end

  def ready?
    loaded && root && !root.value.nil?
  end

  def value
    root.value
  end

  def fullValue
    res = @deps.inject({}) do |ret, k|
      ret[k] = if v = valueForKey(k)
        v.value
      end
      ret
    end
    res
  end

  def propertyValues
    res = @deps.inject({}) do |ret, k|
      ret[k] = valueForKey(k)
      ret
    end
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
