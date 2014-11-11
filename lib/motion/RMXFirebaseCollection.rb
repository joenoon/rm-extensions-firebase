class RMXFirebaseCollection

  def self.get(ref)
    new(ref)
  end

  attr_accessor :snap, :ref, :loaded

  # order will affect future passes through modelsSignalForBaseSignal transformation,
  # so set it before using modelsSignalForBaseSignal-based signals
  attr_accessor :order

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

  def initialize(_ref)
    RMX.log_dealloc(self)
    @loaded = false
    @models = {}

    @readySignal = RMX(self).racObserve("loaded").ignore(false)

    RMX(self).rac["snap"] = RMX(self).racObserve("ref").ignore(nil)
    .map(->(_r) { _r.rac_valueSignal.catchTo(RACSignal.never) }.weak!)
    .switchToLatest

    RMX(self).rac["loaded"] = RMX(self).racObserve("snap").ignore(nil)
    .mapReplace(true)#.setNameWithFormat("READY(#{rmx_object_desc})").logAll

    self.ref = _ref
  end

  def ref_description
    if r = @ref
      r.ref_description
    end
  end

  # public, override required
  def transform(snap)
    raise "#{className}#transform(snap): override to return a RMXFirebaseModel based on the snap"
  end

  def store_transform(snap)
    @models[snap.key] ||= transform(snap)
  end

  def purge_transforms_not_in_keys(keys)
    existing_keys = @models.keys
    old_keys = existing_keys - keys
    old_keys.each do |old_key|
      # p "removing old key", old_key
      @models.delete(old_key)
    end
  end

  def currentLimit
    if r = ref
      if l = r.queryParams && r.queryParams.queryObject["l"]
        l.to_i
      end
    end
  end

  # adjust the current Firebase ref's limit by an increment number
  def limitIncrBy(num)
    if r = ref
      if l = r.queryParams && r.queryParams.queryObject["l"]
        is_left = r.queryParams.queryObject["vf"] == "l"
        new_limit = l.to_i + num
        new_limit = 0 if new_limit < 0
        new_ref = is_left ? r.freshRef.queryLimitedToFirst(new_limit) : r.freshRef.queryLimitedToLast(new_limit)
        self.ref = new_ref
      else
        NSLog("#{className}#limitIncrBy WARNING: tried to increament a non-existent limit for #{r.ref_description}")
      end
    end
  end

  # adjust the current Firebase ref's limit to an exact number
  def limitTo(num)
    if r = ref
      is_left = r.queryParams && r.queryParams.queryObject["vf"] == "l"
      new_ref = is_left ? r.freshRef.queryLimitedToFirst(num) : r.freshRef.queryLimitedToLast(num)
      self.ref = new_ref
    end
  end

  # signals

  include RMXFirebaseSignalHelpers

  def modelsSignalForBaseSignal(base)
    base
    .map(->(m) {
      snaps = m.order == :desc ? m.snap.children.allObjects.reverse : m.snap.children.allObjects
      keys = snaps.map(&:key)
      items = snaps.map { |s| m.store_transform(s) }
      m.purge_transforms_not_in_keys(keys)
      signals = items.map(&:strongOnceSignal)
      RACSignal.concat(signals).collect
    }.weak!)
    .switchToLatest
  end

  # models
  def weakAlwaysModelsSignal
    modelsSignalForBaseSignal(weakAlwaysSignal)
  end

  def weakAlwaysModelsMainSignal
    modelsSignalForBaseSignal(weakAlwaysSignal).deliverOn(RACScheduler.mainThreadScheduler)
  end

  def strongAlwaysModelsSignal
    modelsSignalForBaseSignal(strongAlwaysSignal)
  end

  def strongAlwaysModelsMainSignal
    modelsSignalForBaseSignal(strongAlwaysSignal).deliverOn(RACScheduler.mainThreadScheduler)
  end

  def strongOnceModelsSignal
    modelsSignalForBaseSignal(strongOnceSignal)
  end

  def strongOnceModelsMainSignal
    modelsSignalForBaseSignal(strongOnceSignal).deliverOn(RACScheduler.mainThreadScheduler)
  end

  # added
  def weakAddedSignal
    weakAlwaysSignal
    .map(->(x) {
      if r = x.ref and s = x.snap
        r.rac_addedSignal.skip(s.childrenCount)
      else
        RACSignal.never
      end
    }.weak!)
    .switchToLatest
  end

  def weakAddedMainSignal
    weakAddedSignal.deliverOn(RACScheduler.mainThreadScheduler)
  end

  # added (model)
  def weakAddedModelSignal
    weakAddedSignal.map(->(pair) { [ store_transform(pair[0]), pair[1] ] }.weak!)
  end

  def weakAddedModelMainSignal
    weakAddedMainSignal
    .map(->(pair) {
      model = store_transform(pair[0])
      prev = pair[1]
      arr = [ model, prev ]
      model.strongOnceSignal.mapReplace(arr)
    }.weak!)
    .switchToLatest
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
    weakMovedSignal.map(->(pair) { [ store_transform(pair[0]), pair[1] ] }.weak!)
  end

  def weakMovedModelMainSignal
    weakMovedMainSignal.map(->(pair) { [ store_transform(pair[0]), pair[1] ] }.weak!)
  end

end
