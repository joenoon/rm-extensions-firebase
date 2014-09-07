class RMXFirebaseBatch

  include RMXCommonMethods

  def initialize(*the_models)
    @models = the_models.flatten.compact
    @signals = @models.map(&:readySignal)
    @signal = RACSignal.combineLatestOrEmpty(@signals).subscribeOn(RACScheduler.scheduler)
  end

  def once(scheduler=nil, &block)
    @signal
    .take(1)
    .flattenMap(->(tuple) {
      RACSignal.return(tuple.allObjects)
    })
    .deliverOn(RMXFirebase.rac_schedulerFor(scheduler))
    .subscribeNext(->(v) {
      block.call @models
    })
  end

end
