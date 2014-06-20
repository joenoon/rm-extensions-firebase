module FirebaseExt

  class Coordinator

    include RMExtensions::CommonMethods

    attr_reader :watches

    def initialize
      @watches = {}
    end

    def clear!
      QUEUE.async do
        @cancelled = false
        @ready = false
        keys = watches.keys.dup
        while keys.size > 0
          name = keys.shift
          watch = watches[name]
          watch.stop!
        end
        watches.clear
      end
      self
    end

    def ready?
      !!@ready
    end

    def cancelled?
      !!@cancelled
    end

    def ready!
      QUEUE.async do
        @ready = true
        rmext_trigger(:ready, self)
        rmext_trigger(:finished, self)
      end
    end

    def cancelled!
      QUEUE.async do
        @cancelled = true
        rmext_trigger(:cancelled, self)
        rmext_trigger(:finished, self)
      end
    end

    def stub(name)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      watches[name] ||= Listener.new
    end

    def watch(name, ref, opts={}, &block)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      data = Listener.new
      data.ref = ref
      if opts[:required]
        data.value_required = true
      end
      unless block.nil?
        data.callback = block.weak!
        data.callback_owner = block.owner
      end
      if current = watches[name]
        if current == data || current.description == data.description
          return
        end
        current.stop!
        current.rmext_off(:finished, self)
      end
      watches[name] = data
      data.rmext_on(:finished, :queue => QUEUE) do
        rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
        readies = 0
        cancelled = 0
        size = watches.size
        watches.each_pair do |k, v|
          if v.ready?
            readies += 1
          elsif v.cancelled?
            cancelled += 1
            break
          end
        end
        if cancelled > 0
          cancelled!
        elsif readies == size
          ready!
        end
      end
      data.start!
      data
    end

    def attr(keypath)
      valueForKeyPath(keypath)
    end

    def valueForKey(key)
      watches[key]
    end

    def valueForUndefinedKey(key)
      nil
    end

  end

end
