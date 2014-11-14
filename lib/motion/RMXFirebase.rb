module RMXFirebase

  def self.batchSignal(*models)
    RACSignal.concat(models.flatten.compact.map(&:strongOnceSignal)).collect
  end

  def self.batchMainSignal(*models)
    batchSignal(*models).deliverOn(RACScheduler.mainThreadScheduler)
  end

end
