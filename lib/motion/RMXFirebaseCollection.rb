class RMXFirebaseCollection < RMXFirebaseLiveshot

  # order will affect future passes through modelsSignalForBaseSignal transformation,
  # so set it before using modelsSignalForBaseSignal-based signals
  attr_accessor :order

  # public, override required
  def transform(snap)
    raise "#{className}#transform(snap): override to return a RMXFirebaseModel based on the snap"
  end

  def self.get(ref)
    new(ref)
  end

  def modelsSignalForBaseSignal(base)
    base
    .deliverOn(RMXFirebase.scheduler)
    .map(->(m) {
      snaps = m.order == :desc ? m.childrenArray.reverse : m.childrenArray
      names = snaps.map(&:name)
      items = snaps.map { |s| m.store_transform(s) }
      m.purge_transforms_not_in_names(names)
      signals = items.map(&:strongOnceSignal)
      RACSignal.concat(signals).collect
    }.rmx_unsafe!)
    .switchToLatest
  end

  # models
  def weakAlwaysModelsSignal
    modelsSignalForBaseSignal(weakAlwaysSignal)
  end

  def weakAlwaysModelsMainSignal
    modelsSignalForBaseSignal(weakAlwaysSignal).deliverOn(RACScheduler.mainThreadScheduler)
  end

  def strongOnceModelsSignal
    modelsSignalForBaseSignal(strongOnceSignal)
  end

  def strongOnceModelsMainSignal
    modelsSignalForBaseSignal(strongOnceSignal).deliverOn(RACScheduler.mainThreadScheduler)
  end

  # added
  def weakAddedSignal
    readySignal.takeUntil(rac_willDeallocSignal).take(1).then(-> { ref.rac_addedSignal })
  end

  def weakAddedMainSignal
    weakAddedSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  # added (model)
  def weakAddedModelSignal
    weakAddedSignal.map(->(pair) { [ store_transform(pair[0]), pair[1] ] }.rmx_weak!)
  end

  def weakAddedModelMainSignal
    weakAddedMainSignal.map(->(pair) { [ store_transform(pair[0]), pair[1] ] }.rmx_weak!)
  end

  # removed
  def weakRemovedSignal
    readySignal.takeUntil(rac_willDeallocSignal).take(1).then(-> { ref.rac_removedSignal })
  end

  def weakRemovedMainSignal
    weakRemovedSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  # moved
  def weakMovedSignal
    readySignal.takeUntil(rac_willDeallocSignal).take(1).then(-> { ref.rac_movedSignal })
  end

  def weakMovedMainSignal
    weakMovedSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  # moved (model)
  def weakMovedModelSignal
    weakMovedSignal.map(->(pair) { [ store_transform(pair[0]), pair[1] ] }.rmx_weak!)
  end

  def weakMovedModelMainSignal
    weakMovedMainSignal.map(->(pair) { [ store_transform(pair[0]), pair[1] ] }.rmx_weak!)
  end

  def initialize(ref)
    super
    @models = {}
  end

  def store_transform(snap)
    @models[snap.name] ||= transform(snap)
  end

  def purge_transforms_not_in_names(names)
    existing_names = @models.keys
    old_names = existing_names - names
    old_names.each do |old_name|
      # p "removing old name", old_name
      @models.delete(old_name)
    end
  end

  # adjust the current Firebase ref's limit by an increment number
  def limitIncrBy(num)
    if r = ref
      if l = r.queryParams && r.queryParams.queryObject["l"]
        new_limit = l.to_i + num
        new_limit = 0 if new_limit < 0
        new_ref = r.limited(new_limit)
        self.ref = new_ref
      else
        NSLog("#{className}#limitIncrBy WARNING: tried to increament a non-existent limit for #{r.ref_description}")
      end
    end
  end

  # adjust the current Firebase ref's limit to an exact number
  def limitTo(num)
    if r = ref
      new_ref = r.limited(num)
      self.ref = new_ref
    end
  end

end
