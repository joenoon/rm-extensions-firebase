class RMXFirebaseCollection

  include RMXCommonMethods

  attr_reader :ref, :snaps, :transformations_table, :cancel_error

  # public
  def ready?
    @state == :ready
  end

  # public
  def cancelled?
    @state == :cancelled
  end

  # overridable, by default just returns the snap
  def transform(snap)
    snap
  end

  def transformed_async(&block)
    transformed(:async, &block)
  end

  # public, completes with ready transformations
  def transformed(queue=nil, &block)
    transformed(queue, nil, &block)
  end

  # public, completes with ready transformations
  def transformed(queue=nil, pager=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      starting_at = pager && pager.starting_at
      ending_at = pager && pager.ending_at
      limit = pager && pager.limit
      order = pager && pager.order
      items = []
      first = nil
      last = nil
      max_index = @snaps.size - 1
      if starting_at
        if first = @snaps.index { |x|
          begin
            x.priority >= starting_at
          rescue => e
            p "x.priority: #{x.priority.inspect}, starting_at: #{starting_at.inspect}, e: #{e.inspect}"
          end
        }
          last = first + limit
          last = max_index if last > max_index
        end
      elsif ending_at
        if last = @snaps.rindex { |x| x.priority <= ending_at }
          first = last - limit
          first = 0 if first < 0
        end
      else
        last = @snaps.size - 1
        if last > -1
          if limit
            first = last - limit
          else
            first = 0
          end
          first = 0 if first < 0
        end
      end
      if first && last
        i = first
        while i <= last
          break unless snap = @snaps[i]
          break unless model = store_transform(snap)
          items << model
          i += 1
        end
      end
      if order == :desc
        items = items.reverse
      end
      if (snap = items.first) && snap.is_a?(RMXFirebaseModel)
        RMXFirebaseBatch.new(items).once(queue, &block)
      else
        RMXFirebase.block_on_queue(queue, items, &block)
      end
    end
    self
  end

  # completes with `self` once, when the collection is ready.
  # retains `self` and the sender until complete
  def once(queue=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      if ready?
        RMXFirebase.block_on_queue(queue, self, &block)
      else
        RMX(self).once(:ready, :strong => true, :queue => queue, &block)
      end
    end
    self
  end

  def once_models(queue=nil, &block)
    once(:async) do |collection|
      collection.transformed(&block)
    end
  end

  def once_models(queue=nil, pager=nil, &block)
    once_canceller = once(:async) do |collection|
      collection.transformed(queue, pager, &block)
    end
    pager_canceller = RMX(pager).on(:changed) do
      changed!
    end
    off_block = proc do
      once_canceller.call
      pager_canceller.call
    end
    off_block
  end

  # completes with `self` immediately if ready, and every time the collection :ready fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def always(queue=nil, &block)
    return false if cancelled?
    if ready?
      RMXFirebase.block_on_queue(queue, self, &block)
    end
    RMX(self).on(:ready, :queue => queue, &block)
  end

  def always_models(queue=nil, &block)
    always(:async) do |collection|
      collection.transformed(&block)
    end
  end

  def always_models(queue=nil, pager=nil, &block)
    always_canceller = always(:async) do |collection|
      collection.transformed(queue, pager, &block)
    end
    pager_canceller = RMX(pager).on(:changed) do
      changed!
    end
    off_block = proc do
      always_canceller.call
      pager_canceller.call
    end
    off_block
  end

  # completes with `self` every time the collection :changed fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def changed(queue=nil, &block)
    return false if cancelled?
    RMX(self).on(:changed, :queue => queue, &block)
  end

  # completes with `self`, `snap`, `prev` every time the collection :added fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def added(queue=nil, &block)
    return false if cancelled?
    RMX(self).on(:added, :queue => queue, &block)
  end

  def added_model(queue=nil, &block)
    added(:async) do |collection, snap|
      collection.transform(snap).once(&block)
    end
  end

  # completes with `self`, `snap` every time the collection :removed fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def removed(queue=nil, &block)
    return false if cancelled?
    RMX(self).on(:removed, :queue => queue, &block)
  end

  # completes with `self`, `snap`, `prev` every time the collection :moved fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def moved(queue=nil, &block)
    return false if cancelled?
    RMX(self).on(:moved, :queue => queue, &block)
  end

  def initialize(_ref)
    @snaps_by_name = {}
    @snaps = []
    @transformations_table = {}
    @added_handler = nil
    @removed_handler = nil
    @moved_handler = nil
    @value_handler = nil
    @cancel_error = nil
    @ref = nil
    @root = nil
    setup_ref(_ref)
  end

  # internal
  def setup_ref(_ref)
    _clear_current_ref!
    @ref = _ref
    @root = Firebase.alloc.initWithRepo(_ref.repo, andPath:_ref.path)
    RMXFirebase::QUEUE.barrier_async do
      cancel_block = lambda do |err|
        @cancel_error = err
        cancelled!
      end
      @added_handler = _ref.on(:added) do |snap, prev|
        # p "NORMAL ", snap.name, prev
        RMXFirebase::QUEUE.barrier_async do
          # p "BARRIER", snap.name, prev
          add(snap, prev)
        end
      end
      @removed_handler = _ref.on(:removed) do |snap|
        RMXFirebase::QUEUE.barrier_async do
          remove(snap)
        end
      end
      @moved_handler = _ref.on(:moved) do |snap, prev|
        RMXFirebase::QUEUE.barrier_async do
          add(snap, prev)
        end
      end
      @value_handler = @root.on(:value, { :disconnect => cancel_block }) do |collection|
        RMXFirebase::QUEUE.barrier_async do
          ready! unless ready?
        end
      end
      RMX(self).on(:cancelled, :exclusive => [ :ready, :changed, :added, :removed, :moved ], :queue => :async)
    end
  end

  def _clear_current_ref!
    # p "_clear_current_ref"
    if @added_handler
      @ref.off(@added_handler)
      @added_handler = nil
    end
    if @removed_handler
      @ref.off(@removed_handler)
      @removed_handler = nil
    end
    if @moved_handler
      @ref.off(@moved_handler)
      @moved_handler = nil
    end
    if @value_handler
      @root.off(@value_handler)
      @value_handler = nil
    end
    @ref = nil
    @root = nil
    @state = nil
  end

  # internal
  def ready!
    RMXFirebase::QUEUE.barrier_async do
      @state = :ready
      changed!
    end
  end

  # internal
  def cancelled!
    RMXFirebase::QUEUE.barrier_async do
      @state = :cancelled
      RMX(self).trigger(:cancelled, self)
      RMX(self).trigger(:finished, self)
    end
  end

  # internal
  def changed!
    RMXFirebase::QUEUE.barrier_async do
      RMX(self).trigger(:changed, self)
      if ready?
        RMX(self).trigger(:ready, self)
        RMX(self).trigger(:finished, self)
      end
    end
  end

  # internal
  def store_transform(snap)
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    @transformations_table[snap] ||= begin
      model = transform(snap)
      RMX(model).on(:cancelled, :queue => :async) do
        changed!
      end
      model
    end
  end

  # internal
  def add(snap, prev)
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    moved = false

    if current_index = @snaps_by_name[snap.name]
      if current_index == 0 && prev.nil?
        return
      elsif current_index > 0 && prev && @snaps_by_name[prev] == current_index - 1
        return
      end
      moved = true
      @snaps.delete_at(current_index)
      if was_index = @snaps_by_name.delete(snap.name)
        @snaps_by_name.keys.each do |k|
          v = @snaps_by_name[k]
          if v > was_index
            @snaps_by_name[k] -= 1
          end
        end
      end
      # raise if snaps_by_name.values.uniq.size != snaps_by_name.values.size
    end
    # raise if snaps_by_name.values.uniq.size != snaps_by_name.values.size
    if prev && (index = @snaps_by_name[prev])
      new_index = index + 1
      @snaps.insert(new_index, snap)
      @snaps_by_name.keys.each do |k|
        v = @snaps_by_name[k]
        if v >= new_index
          @snaps_by_name[k] += 1
        end
      end
      @snaps_by_name[snap.name] = new_index
      # raise if snaps_by_name.values.uniq.size != snaps_by_name.values.size
    else
      @snaps.unshift(snap)
      @snaps_by_name.keys.each do |k|
        v = @snaps_by_name[k]
        @snaps_by_name[k] += 1
      end
      @snaps_by_name[snap.name] = 0
      # raise if snaps_by_name.values.uniq.size != snaps_by_name.values.size
    end
    if moved
      RMX(self).trigger(:moved, self, snap, prev)
    else
      RMX(self).trigger(:added, self, snap, prev)
    end
    changed!
  end

  # internal
  def remove(snap)
    if current_index = @snaps_by_name[snap.name]
      @snaps.delete_at(current_index)
      @snaps_by_name.keys.each do |k|
        v = @snaps_by_name[k]
        if v > current_index
          @snaps_by_name[k] -= 1
        end
      end
      RMX(self).trigger(:removed, self, snap)
      changed!
    end
  end

  # this is the method you should call
  def self.get(ref)
    if ref && existing = identity_map[[ className, ref.description ]]
      if RMXFirebase::DEBUG_IDENTITY_MAP
        p "HIT!", className, ref.description, existing.retainCount
      end
      return existing
    else
      if RMXFirebase::DEBUG_IDENTITY_MAP
        p "MISS!", className, ref.description
      end
      res = new(ref)
      if ref
        identity_map[[ className, ref.description ]] = res
      end
      res
    end
  end

  Dispatch.once do
    @@identity_map = RMXSynchronizedStrongToWeakHash.new
  end

  def self.identity_map
    @@identity_map
  end

end
