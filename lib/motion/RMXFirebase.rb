module RMXFirebase

  def self.scheduler
    RMXRACHelper.schedulerWithHighPriority
  end

  def self.batchSignal(*models)
    RACSignal.concat(models.flatten.compact.map(&:strongOnceSignal)).collect
  end

  def self.batchMainSignal(*models)
    batch(*models).deliverOn(RACScheduler.mainThreadScheduler)
  end

end
