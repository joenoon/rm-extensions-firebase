class RMXFirebaseBatch

  include RMXCommonMethods

  def self.new(*models)
    _models = models.dup
    _models = _models.flatten.compact
    x = super()
    RMXFirebase::QUEUE.barrier_async do
      x.setup_models(_models)
    end
    x
  end

  def initialize
    @models = []
    @ready_models = []
    @complete_blocks = {}
  end

  def setup_models(the_models)
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    @ready = false
    @models = the_models.dup
    @ready_count = 0
    @pending_count = @models.size
    if @models.any?
      _models = @models.dup
      _pairs = []
      i = 0
      while _models.size > 0
        ii = i # strange: proc doesnt seem to close over i correctly
        model = _models.shift
        blk = proc do
          RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
          # p "COMPLETE!", ii, model
          @complete_blocks.delete(model)
          @ready_models[ii] = model
          @ready_count += 1
          @pending_count -= 1
          if @pending_count == 0
            ready!
          end
        end
        @complete_blocks[model] = blk
        _pairs << [ model, blk ]
        i += 1
      end
      RMXFirebase::QUEUE.barrier_async do
        while pair = _pairs.shift
          pair[0].once(RMXFirebase::QUEUE, &pair[1])
        end
      end
    else
      RMXFirebase::QUEUE.barrier_async do
        ready!
      end
    end
  end

  def ready!
    RMXFirebase::QUEUE.barrier_async do
      @ready = true
      # p "models", models.dup
      # p "ready_models", ready_models.dup
      RMX(self).trigger(:ready, @ready_models.dup)
    end
  end

  def cancel!
    RMXFirebase::QUEUE.barrier_async do
      models_outstanding = @complete_blocks.keys.dup
      while models_outstanding.size > 0
        model = models_outstanding.shift
        if blk = @complete_blocks[model]
          @complete_blocks.delete(model)
          model.cancel_block(&blk)
        end
      end
    end
  end

  def ready?
    !!@ready
  end

  def once(queue=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      if ready?
        RMXFirebase.block_on_queue(queue, @ready_models.dup, &block)
      else
        RMX(self).once(:ready, :strong => true, :queue => queue, &block)
      end
    end
    self
  end

  def cancel_block(&block)
    RMX(self).off(:ready, &block)
  end

end
