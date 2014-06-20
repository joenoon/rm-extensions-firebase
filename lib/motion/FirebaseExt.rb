module FirebaseExt

  QUEUE = Dispatch::Queue.new("FirebaseExt")

  DEBUG_IDENTITY_MAP = RMExtensions::Env['rmext_firebase_debug_identity_map'] == '1'
  DEBUG_MODEL_DEALLOC = RMExtensions::Env['rmext_firebase_debug_model_dealloc'] == '1'
  DEBUG_FIREBASE_TIMING = RMExtensions::Env['rmext_firebase_debug_timing'] == '1'

  def self.queue_for(queueish)
    if queueish == :main || queueish.nil?
      Dispatch::Queue.main
    elsif queueish == :async
      QUEUE
    else
      queueish
    end
  end

  def self.block_on_queue(queue, *args, &block)
    queue = queue_for(queue)
    if queue == Dispatch::Queue.main && NSThread.currentThread.isMainThread
      block.call(*args)
    else
      queue.barrier_async do
        block.call(*args)
      end
    end
  end

end
