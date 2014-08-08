class RMXFirebaseBatch

  include RMXCommonMethods

  def initialize(*the_models)
    @state = nil
    @models = []
    @ready_models = []
    @complete_blocks = {}
    setup_models(the_models)
  end

  def setup_models(the_models)
    @models = the_models.dup.flatten.compact
    @ready_count = 0
    @pending_count = @models.size
    RMXFirebase::QUEUE.barrier_async do
      _models = @models.dup
      if _models.any?
        _pairs = []
        i = 0
        while _models.size > 0
          ii = i # strange: proc doesnt seem to close over i correctly
          model = _models.shift
          blk = proc do
            RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
            # p "COMPLETE!", ii, model
            @complete_blocks.delete(model)
            if model.ready?
              @ready_models[ii] = model
            end
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
            pair[0].once_finished(RMXFirebase::QUEUE, &pair[1])
          end
        end
      else
        RMXFirebase::QUEUE.barrier_async do
          ready!
        end
      end
    end
  end

  def ready!
    RMXFirebase::QUEUE.barrier_async do
      @state = :ready
      # p "models", models.dup
      # p "ready_models", ready_models.dup
      RMX(self).trigger(:ready, @ready_models.compact)
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
    @state == :ready
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
