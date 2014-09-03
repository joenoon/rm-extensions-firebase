class RMXFirebaseBatch

  include RMXCommonMethods

  def initialize(*the_models)
    setup_models(the_models)
  end

  def setup_models(the_models)
    signals = the_models.flatten.compact.map(&:rac_valueSignal)
    @signal = RACSignal.combineLatestOrEmptyToArray(signals)
  end

  def once(queue=nil, &block)
    @signal.take(1).subscribeNext(block)
  end

end
