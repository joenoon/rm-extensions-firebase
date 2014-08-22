class RMXFirebaseBatch

  include RMXCommonMethods

  def initialize(*the_models)
    @state = nil
    @models = []
    @finished_models = []
    @complete_blocks = {}
    setup_models(the_models)
  end

  def setup_models(the_models)
    @models = the_models.dup.flatten.compact
    @finished_count = 0
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
            @finished_models[ii] = model
            @finished_count += 1
            @pending_count -= 1
            if @pending_count == 0
              finished!
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
          finished!
        end
      end
    end
  end

  def finished!
    RMXFirebase::QUEUE.barrier_async do
      @state = :finished
      RMX(self).trigger(:finished, @finished_models.dup)
    end
  end

  def cancel!
    RMX(self).off(:finished)
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

  def finished?
    @state == :finished
  end

  def once(queue=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      if finished?
        RMXFirebase.block_on_queue(queue, @finished_models.dup, &block)
      else
        RMX(self).once(:finished, :strong => true, :queue => queue, &block)
      end
    end
    nil
  end

  def cancel_block(&block)
    RMX(self).off(:finished, &block)
  end

end
