module RMXFirebase

  def self.allNextOrCompleted(signals)
    groups = signals.each_slice(100).to_a.map { |x| x.size > 0 ? RACSignal.combineLatest(x).take(1).rmx_expandTuple : RACSignal.return([]) }
    all = groups.size > 0 ? RACSignal.combineLatest(groups).take(1).rmx_expandTuple : RACSignal.return([])
    all.map(->(x) { x.flatten })
  end

  def self.allNextOrCompletedSequential(signals, jitter:jitter)
    groups = signals.each_slice(100).to_a.map { |x| x.size > 0 ? RACSignal.concat(x).collect.rmx_expandTuple.delay(jitter) : RACSignal.return([]) }
    all = groups.size > 0 ? RACSignal.concat(groups).collect.rmx_expandTuple : RACSignal.return([])
    all.map(->(x) { x.flatten })
  end

  def self.allNextOrCompletedSequential(signals)
    groups = signals.each_slice(100).to_a.map { |x| x.size > 0 ? RACSignal.concat(x).collect.rmx_expandTuple : RACSignal.return([]) }
    all = groups.size > 0 ? RACSignal.concat(groups).collect.rmx_expandTuple : RACSignal.return([])
    all.map(->(x) { x.flatten })
  end

  def self.batchSignal(*models)
    allNextOrCompletedSequential(models.flatten.compact.map(&:strongOnceSignal))
  end

  def self.batchMainSignal(*models)
    batchSignal(*models).deliverOn(RACScheduler.mainThreadScheduler)
  end

end
