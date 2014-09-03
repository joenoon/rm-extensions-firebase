# to get models to show up in Instruments, for some reason need to < UIResponder 
class RMXFirebaseModel

  RECURSIVE_LOCK = NSRecursiveLock.new
  
  include RMXCommonMethods

  attr_accessor :root, :opts

  def initialize(attrs={})
    self.attributes = attrs
    RMX.log_dealloc(self)
    self
  end

  def cache_key
    RECURSIVE_LOCK.lock
    res = [ _type, opts ]
    RECURSIVE_LOCK.unlock
    res
  end

  def ref
    RECURSIVE_LOCK.lock
    res = self.class.get(opts)
    RECURSIVE_LOCK.unlock
    res
  end

  def attributes=(attrs)
    RECURSIVE_LOCK.lock
    keys = [] + attrs.keys
    while key = keys.pop
      value = attrs[key]
      self.send("#{key}=", value)
    end
    RECURSIVE_LOCK.unlock
  end

  def attr(keypath)
    RECURSIVE_LOCK.lock
    res = @root.attr(keypath)
    RECURSIVE_LOCK.unlock
    res
  end

  def hasValue?
    RECURSIVE_LOCK.lock
    res = @root.hasValue?
    RECURSIVE_LOCK.unlock
    res
  end

  def toValue
    RECURSIVE_LOCK.lock
    res = @root.toValue
    RECURSIVE_LOCK.unlock
    res
  end

  def self.setup(opts)
    raise "unimplemented: #{className}.setup"
  end

  def self.signalsToValues(hash_of_signals)
    signalsToValues(hash_of_signals, mergeWith:nil)
  end

  def self.signalsToValues(hash_of_signals, mergeWith:existing_hash)
    existing_hash ||= {}
    existing_hash = existing_hash.dup
    keys = hash_of_signals.keys
    signals = hash_of_signals.values
    RACSignal.combineLatestOrEmpty(signals)
    .flattenMap(->(tuple) {
      keys.each_with_index do |k, i|
        existing_hash[k] = tuple[i]
      end
      RACSignal.return(existing_hash)
    })
  end

  def self.get(opts=nil)
    RMXFirebaseModelQuery.new(self, opts)
  end

end
