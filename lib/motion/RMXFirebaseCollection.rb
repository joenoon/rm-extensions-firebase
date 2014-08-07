class RMXFirebaseCollection

  include RMXCommonMethods

  attr_reader :ref, :snaps, :transformations, :transformations_table, :cancel_error

  # public
  def ready?
    @state == :ready
  end

  # public
  def cancelled?
    @state == :cancelled
  end

  # overridable
  def transform(snap)
    if block = @transform_block
      block.call(snap)
    else
      snap
    end
  end

  def transformed_async(&block)
    transformed(:async, &block)
  end

  # public, completes with ready transformations
  def transformed(queue=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      items = @transformations.dup
      if (snap = items.first) && snap.is_a?(RMXFirebaseModel)
        RMXFirebaseBatch.new(items).once(queue, &block)
      else
        RMXFirebase.block_on_queue(queue, items, &block)
      end
    end
    self
  end

  def once_async(&block)
    once(:async, &block)
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

  def always_async(&block)
    always(:async, &block)
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
    @transformations = []
    @added_handler = nil
    @removed_handler = nil
    @moved_handler = nil
    @value_handler = nil
    @cancel_error = nil
    setup_ref(_ref)
  end

  # internal
  def setup_ref(_ref)
    _clear_current_ref!
    @ref = _ref
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
      @value_handler = _ref.once(:value, { :disconnect => cancel_block }) do |collection|
        @value_handler = nil
        RMXFirebase::QUEUE.barrier_async do
          ready!
        end
      end
      RMX(self).on(:cancelled, :exclusive => [ :ready, :finished, :changed, :added, :removed, :moved ], :queue => :async)
    end
  end

  def _clear_current_ref!
    if _ref = @ref
      if @added_handler
        _ref.off(@added_handler)
        @added_handler = nil
      end
      if @removed_handler
        _ref.off(@removed_handler)
        @removed_handler = nil
      end
      if @moved_handler
        _ref.off(@moved_handler)
        @moved_handler = nil
      end
      if @value_handler
        _ref.off(@value_handler)
        @value_handler = nil
      end
    end
    @state = nil
  end

  # internal
  def ready!
    RMXFirebase::QUEUE.barrier_async do
      @state = :ready
      RMX(self).trigger(:ready, self)
      RMX(self).trigger(:changed, self)
      RMX(self).trigger(:finished, self)
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

  # internal, allows the user to pass a block for transformations instead of subclassing
  # and overriding #transform, for one-off cases
  def transform=(block)
    if block
      @transform_block = RMX.safe_block(block)
    else
      @transform_block = nil
    end
  end

  # internal
  def store_transform(snap)
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    @transformations_table[snap] ||= transform(snap)
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
      @transformations.delete_at(current_index)
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
      @transformations.insert(new_index, store_transform(snap))
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
      @transformations.unshift(store_transform(snap))
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
    RMX(self).trigger(:changed, self)
    if ready?
      RMX(self).trigger(:ready, self)
      RMX(self).trigger(:finished, self)
    end
  end

  # internal
  def remove(snap)
    if current_index = @snaps_by_name[snap.name]
      @snaps.delete_at(current_index)
      @transformations.delete_at(current_index)
      @snaps_by_name.keys.each do |k|
        v = @snaps_by_name[k]
        if v > current_index
          @snaps_by_name[k] -= 1
        end
      end
      RMX(self).trigger(:removed, self, snap)
      RMX(self).trigger(:changed, self)
      if ready?
        RMX(self).trigger(:ready, self)
        RMX(self).trigger(:finished, self)
      end
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
