class RMXFirebaseBatch

  include RMXCommonMethods

  def initialize(*the_models)
    @models = the_models.flatten.compact
    @signals = @models.map(&:readySignal)
    @signal = RACSignal.combineLatestOrEmptyToArray(@signals)
  end

  def once(scheduler=nil, &block)
    @signal
    .take(1)
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(->(v) {
      block.call @models
    })
  end

end
