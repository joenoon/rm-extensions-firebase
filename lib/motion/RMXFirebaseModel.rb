# to get models to show up in Instruments, for some reason need to < UIResponder 
class RMXFirebaseModel

  include RMXCommonMethods

  include RMXFirebaseSignalHelpers
  
  def self.get(opts=nil)
    new(opts)
  end

  def self.property(name)
    attr_accessor name
    attr_accessor "#{name}_satisfied"
  end

  property :root

  NIL_SIG = RACSignal.return(nil)
  TRUE_SIG = RACSignal.return(true)

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
    @deps = []
    @dep_sigs = []
    @opts = opts
    @loaded = false

    @readySignal = RMX(self).racObserve("loaded").ignore(false)

    setup

    RMX(self).rac["loaded"] = RACSignal.combineLatest(@dep_sigs)
    .takeUntil(rac_willDeallocSignal)
    .map(->(x) {
      root && !root.value.nil?
    }.weak!)#.setNameWithFormat("(#{rmx_object_desc}) READY").logAll

  end

  def depend(name, opts)
    satisfied_key = "#{name}_satisfied"
    dep_sig = if signal = opts[:signal]
      signal
    else
      model = opts[:model]
      parts = opts[:keypath].split(".")
      dep_satisfied_key = "*self*"
      dep_on_sig = if parts.first == "self"
        parts.shift
        TRUE_SIG
      else
        dep_satisfied_key = "#{parts.first}_satisfied"
        RMX(self).racObserve(dep_satisfied_key).ignore(nil)
      end
      keypath = parts.join(".")
      dep_on_sig#.setNameWithFormat("(#{rmx_object_desc}) #{name} check because of #{dep_satisfied_key}").logAll
      .takeUntil(rac_willDeallocSignal)
      .map(->(x) {
        valueForKeyPath(keypath)
      }.weak!)#.setNameWithFormat("(#{rmx_object_desc}) #{name} opts for keypath #{keypath}").logAll
      .distinctUntilChanged
      .map(->(opts) {
        if opts
          # p "depend", name, "send strongSingal", "model", model, "opts", opts
          model.get(opts).strongAlwaysSignal
        else
          # p "depend", name, "send nilSignal"
          NIL_SIG
        end
      }.weak!)
      .switchToLatest#.setNameWithFormat("(#{rmx_object_desc}) #{name} result for keypath #{keypath}").logAll
    end
    .doNext(->(x) {
      unless x.nil?
        # p "setValue", "forKey", name, "val", x
        setValue(x, forKey:name)
        # p "setValue date", "forKey", satisfied_key
        setValue(NSDate.date, forKey:satisfied_key)
      end
    }.weak!)#.setNameWithFormat("(#{rmx_object_desc}) #{name} complete for keypath #{keypath}").logAll
    @deps << name
    @dep_sigs << dep_sig
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
