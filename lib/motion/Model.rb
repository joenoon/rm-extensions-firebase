module FirebaseExt

  class Model
    
    include RMExtensions::CommonMethods

    attr_accessor :opts

    attr_reader :api, :root

    def queue
      QUEUE
    end

    def self.new(opts=nil)
      x = super
      QUEUE.async do
        x.internal_setup
      end
      x
    end

    def initialize(opts=nil)
      @opts = opts
      @dependencies_cancelled = {}
      @dependencies_ready = {}
      @dependencies = {}
    end

    def dealloc
      if DEBUG_MODEL_DEALLOC
        p " - dealloc!"
      end
      super
    end

    def ready?
      !!@ready
    end

    def cancelled?
      !!@cancelled
    end

    def finished?
      ready? || cancelled?
    end

    def ready!
      QUEUE.async do
        # p "ready!"
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

    # override
    def setup
    end

    def internal_setup
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      @api = Coordinator.new
      @api.rmext_on(:finished, :queue => QUEUE) do
        rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
        check_ready
      end
      rmext_on(:cancelled, :exclusive => [ :ready, :finished ], :queue => :async)
      setup
    end

    def check_ready
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      # p "check_ready cancelled?", @api.cancelled?, dependencies_cancelled.size
      # p "check_ready ready?", @api.ready?, dependencies_ready.size, dependencies.size
      if @api.cancelled? || @dependencies_cancelled.size > 0
        cancelled!
      elsif @api.ready? && @dependencies_ready.size == @dependencies.size
        ready!
      end
    end

    def watch(name, ref, opts={}, &block)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      rmext_ivar(name, @api.watch(name, ref, opts, &block))
    end

    # add another model as a dependency and ivar,
    # which will affect ready.  should be done before ready has
    # has a chance to be triggered.  the user can add an
    # attr_reader for easy access if desired.
    #
    # Book
    #   attr_reader :author
    #   model.watch(:root, ref) do |data|
    #     model.depend(:author, Author.get(data[:author_id]))
    #   end
    # ...
    # book = Book.get(1)
    # book.attr("name") #=> "My Book"
    # book.author.attr("name") #=> "Joe Noon"
    def depend(name, model)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      @dependencies[name] = model
      rmext_ivar(name, model)
      track_dependency_state(model)
      model.rmext_on(:finished, :queue => QUEUE) do |_model|
        rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
        track_dependency_state(_model)
        check_ready
      end
    end

    def track_dependency_state(model)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      if model.ready?
        @dependencies_ready[model] = true
        @dependencies_cancelled.delete(model)
      elsif model.cancelled?
        @dependencies_cancelled[model] = true
        @dependencies_ready.delete(model)
      end
    end

    def always_async(&block)
      always(:async, &block)
    end

    def always(queue=nil, &block)
      return false if cancelled?
      if ready?
        FirebaseExt.block_on_queue(queue, self, &block)
      end
      rmext_on(:ready, :queue => queue, &block)
    end

    # Model
    def once(queue=nil, &block)
      QUEUE.async do
        if ready? || cancelled?
          FirebaseExt.block_on_queue(queue, self, &block)
        else
          rmext_once(:ready, :strong => true, :queue => queue, &block)
        end
      end
      self
    end

    def cancel_block(&block)
      rmext_off(:ready, &block)
      rmext_off(:cancelled, &block)
      rmext_off(:finished, &block)
    end

    def attr(keypath)
      root.attr(keypath)
    end

    def hasValue?
      root.hasValue?
    end

    def toValue
      root.toValue
    end

    def self.create(&block)
      x = new
      block.call(x)
      x
    end

    # this is the method you should call
    def self.get(opts=nil)
      if opts && existing = identity_map[[ className, opts ]]
        if DEBUG_IDENTITY_MAP
          p "HIT!", className, opts, existing.retainCount
        end
        return existing
      else
        if DEBUG_IDENTITY_MAP
          p "MISS!", className, opts
        end
        res = new(opts)
        if opts
          identity_map[[ className, opts ]] = res
        end
        res
      end
    end

    Dispatch.once do
      @@identity_map = RMExtensions::IdentityMap.new
    end

    def self.identity_map
      @@identity_map
    end

  end

end
