module RMXFirebase

  def self.batchSignal(*models)
    ms = models.flatten.compact
    if ms.size == 0
      RACSignal.return([])
    else
      sigs = ms.map(&:strongOnceSignal)
      RACSignal.merge(sigs)
      .ignoreValues
      .concat(RACSignal.return(ms))
    end
  end

  def self.batchMainSignal(*models)
    batchSignal(*models).deliverOn(RACScheduler.mainThreadScheduler)
  end

end
