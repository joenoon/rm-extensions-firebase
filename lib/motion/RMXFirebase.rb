module RMXFirebase

  QUEUE = Dispatch::Queue.new("RMXFirebase")
  INTERNAL_QUEUE = Dispatch::Queue.new("RMXFirebase.internal")

  DEBUG_IDENTITY_MAP = RMX::Env['rmx_firebase_debug_identity_map'] == '1'

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
Firebase.setDispatchQueue(RMXFirebase::INTERNAL_QUEUE.dispatch_object)
