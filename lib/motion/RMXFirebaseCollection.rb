class RMXFirebaseCollection

  include RMXCommonMethods

  attr_reader :ref, :snaps, :cancel_error

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
        while i < last
          break unless snap = @snaps[i]
          break unless model = transform(snap)
          items << model
          i += 1
        end
      end
      if last_snaps = @last_snaps
        removed = (last_snaps - @snaps).map { |x| transform(x) }
        added = (@snaps - last_snaps).map { |x| transform(x) }
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
      @last_snaps = @snaps.dup
      if order == :desc
        items = items.reverse
      end
      RMXFirebaseBatch.new(items).once(queue, &block)
    end
    self
  end

  # completes with `self` once, when the collection is changed.
  # retains `self` and the sender until complete
  def once(queue=nil, &block)
    if finished?
      RMXFirebase.block_on_queue(queue, self, &block)
    else
      RMX(self).once(:finished, :strong => true, :queue => queue, &block)
    end
  end

  # completes with `self` immediately if changed, and every time the collection changes.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def always(queue=nil, &block)
    if finished?
      RMXFirebase.block_on_queue(queue, self, &block)
    end
    RMX(self).on(:finished, :queue => queue, &block)
  end

  # completes with `self` every time the collection changes.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def changed(queue=nil, &block)
    unless cancelled?
      RMX(self).on(:finished, :queue => queue, &block)
    end
  end

  # completes with `models` once, when the collection is changed.
  # takes optional pager.
  # retains `self` and the sender until complete
  def once_models(queue=nil, pager=nil, &block)
    once_canceller = once(:async) do |collection|
      collection.transformed(queue, pager, &block)
    end
    pager_canceller = if pager
      RMX(pager).on(:changed) do
        finished!
      end
    end
    off_block = proc do
      once_canceller.call
      if pager_canceller
        pager_canceller.call
      end
    end
    off_block
  end

  # completes with `models` immediately if changed, and every time the collection changes.
  # does not retain `self` or the sender.
  # takes optional pager.
  # returns an "unbinder" that can be called to stop listening.
  def always_models(queue=nil, pager=nil, &block)
    always_canceller = always(:async) do |collection|
      collection.transformed(queue, pager, &block)
    end
    pager_canceller = if pager
      RMX(pager).on(:changed) do
        finished!
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
    changed_canceller = changed(:async) do |collection|
      collection.transformed(queue, pager, &block)
    end
    pager_canceller = if pager
      RMX(pager).on(:changed) do
        finished!
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
    RMX(self).on(:added_model, :queue => :async) do |model|
      RMXFirebase.block_on_queue(queue, model, &block)
    end
  end

  # completes with `model` every time the collection :removed fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def removed(queue=nil, &block)
    RMX(self).on(:removed_model, :queue => :async) do |model|
      RMXFirebase.block_on_queue(queue, model, &block)
    end
  end

  # internal
  def initialize(_ref)
    @snaps = []
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
          @snaps = collection.children
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
