class RMXFirebaseCollection

  include RMXCommonMethods

  attr_reader :ref, :snaps, :snapshot, :cancel_error

  # public, override required
  def transform(snap)
    raise "#{className}#transform(snap): override to return a RMXFirebaseModel based on the snap"
  end

  # public
  def ready?
    @state == :ready
  end

  # public
  def cancelled?
    @state == :cancelled
  end

  # public
  def finished?
    @state || false
  end

  # public, completes with changed transformations
  def transformed(queue=nil, pager=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      range = pager && pager.range
      order = pager && pager.order

      # p @ref.description, "range", range.inspect, "order", order.inspect
      
      snaps = order == :desc ? @snaps.reverse : @snaps
      snaps = range ? snaps[range] : snaps
      items = snaps.map { |snap| transform(snap) }

      last_snaps = @last_snaps
      snaps = @snaps.dup
      if last_snaps
        compare_snaps!(snaps, last_snaps.dup)
      end
      @last_snaps = snaps

      RMXFirebaseBatch.new(items).once(queue, &block)
    end
    self
  end

  def compare_snaps!(current, prev)
    RMXFirebase::QUEUE.barrier_async do
      removed = (prev - current).map { |x| transform(x) }
      added = (current - prev).map { |x| transform(x) }
      if removed.size > 0
        RMXFirebaseBatch.new(removed).once(:async) do |removed_models|
          removed_models.each do |removed_model|
            RMX(self).trigger(:removed_model, removed_model)
          end
        end
      end
      if added.size > 0
        RMXFirebaseBatch.new(added).once(:async) do |added_models|
          added_models.each do |added_model|
            RMX(self).trigger(:added_model, added_model)
          end
        end
      end
    end
  end

  # completes with `self` once, when the collection is changed.
  # retains `self` and the sender until complete
  def once(queue=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      if finished?
        RMXFirebase.block_on_queue(queue, self, &block)
      else
        RMX(self).once(:finished, :strong => true, :queue => queue, &block)
      end
    end
    nil
  end

  # completes with `self` immediately if changed, and every time the collection changes.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def always(queue=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      if finished?
        RMXFirebase.block_on_queue(queue, self, &block)
      end
    end
    RMX(self).on(:finished, :queue => queue, &block)
  end

  # completes with `self` every time the collection changes.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def changed(queue=nil, &block)
    RMX(self).on(:finished, :queue => queue, &block)
  end

  # completes with `models` once, when the collection is changed.
  # takes optional pager.
  # retains `self` and the sender until complete
  def once_models(queue=nil, pager=nil, &block)
    once(:async) do |collection|
      collection.transformed(queue, pager, &block)
    end
    nil
  end

  # completes with `models` immediately if changed, and every time the collection changes.
  # does not retain `self` or the sender.
  # takes optional pager.
  # returns an "unbinder" that can be called to stop listening.
  def always_models(queue=nil, pager=nil, &block)
    sblock = RMX.safe_block(block)
    always_canceller = always(:async) do |collection|
      collection.transformed(queue, pager, &sblock)
    end
    pager_canceller = if pager
      RMX(pager).on(:changed, :queue => RMXFirebase::QUEUE) do
        finished! if finished?
      end
    end
    off_block = proc do
      always_canceller.call
      if pager_canceller
        pager_canceller.call
      end
    end
    off_block
  end

  # completes with `models` every time the collection changes.
  # does not retain `self` or the sender.
  # takes optional pager.
  # returns an "unbinder" that can be called to stop listening.
  def changed_models(queue=nil, pager=nil, &block)
    sblock = RMX.safe_block(block)
    changed_canceller = changed(:async) do |collection|
      collection.transformed(queue, pager, &sblock)
    end
    pager_canceller = if pager
      RMX(pager).on(:changed, :queue => RMXFirebase::QUEUE) do
        finished! if finished?
      end
    end
    off_block = proc do
      changed_canceller.call
      if pager_canceller
        pager_canceller.call
      end
    end
    off_block
  end

  # completes with `model` every time the collection :added_model fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def added_model(queue=nil, &block)
    sblock = RMX.safe_block(block)
    RMX(self).on(:added_model, :queue => :async) do |model|
      RMXFirebase.block_on_queue(queue, model, &sblock)
    end
  end

  # completes with `model` every time the collection :removed fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def removed_model(queue=nil, &block)
    sblock = RMX.safe_block(block)
    RMX(self).on(:removed_model, :queue => :async) do |model|
      RMXFirebase.block_on_queue(queue, model, &sblock)
    end
  end

  # internal
  def initialize(_ref)
    @snaps = []
    @snapshot = nil
    @value_handler = nil
    @cancel_error = nil
    @ref = nil
    @state = nil
    setup_ref(_ref)
  end

  # internal
  def setup_ref(_ref)
    _clear_current_ref!
    RMX.synchronized do
      @ref = _ref
      cancel_block = lambda do |err|
        @cancel_error = err
        cancelled!
      end
      @value_handler = _ref.on(:value, { :disconnect => cancel_block }) do |collection|
        RMXFirebase::QUEUE.barrier_async do
          @snapshot = collection
          @snaps = collection.childrenArray
          ready!
        end
      end
    end
  end

  def _clear_current_ref!
    RMX.synchronized do
      # p "_clear_current_ref"
      if @value_handler
        @ref.off(@value_handler)
        @value_handler = nil
      end
      @ref = nil
      @state = nil
    end
  end

  # internal
  def ready!
    RMXFirebase::QUEUE.barrier_async do
      @state = :ready
      finished!
    end
  end

  # internal
  def cancelled!
    RMXFirebase::QUEUE.barrier_async do
      @state = :cancelled
      finished!
      on_cancelled
    end
  end

  # public, overridable
  def on_cancelled
  end

  def stateInfo
    info = []
    # prevent infinite loop if cancelled models point to each other
    return info if @processingCancelInfo
    @processingCancelInfo = true
    info << {
      :ref => @ref.description,
      :state => @state,
      :error => (@cancel_error && @cancel_error.localizedDescription || nil)
    }
    @processingCancelInfo = false
    info
  end

  # internal
  def finished!
    RMXFirebase::QUEUE.barrier_async do
      RMX(self).trigger(:finished, self)
    end
  end

  # this is the method you should call
  def self.get(ref)
    if ref && (existing = identity_map[[ className, ref.description ]]) && !existing.cancelled?
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
