class RMXFirebaseModel
  
  include RMXCommonMethods

  attr_accessor :opts

  attr_reader :api, :root

  def initialize(opts=nil)
    @opts = opts
    @dependencies_cancelled = {}
    @dependencies_ready = {}
    @dependencies = {}
    internal_setup
  end

  def dealloc
    if RMXFirebase::DEBUG_MODEL_DEALLOC
      p " - dealloc!"
    end
    super
  end

  def ready?
    @state == :ready
  end

  def cancelled?
    @state == :cancelled
  end

  def finished?
    ready? || cancelled?
  end

  def ready!
    RMXFirebase::QUEUE.barrier_async do
      # p "ready!", toValue
      @state = :ready
      RMX(self).trigger(:ready, self)
      RMX(self).trigger(:finished, self)
    end
  end

  def cancelled!
    RMXFirebase::QUEUE.barrier_async do
      # p "cancelled!", toValue
      @state = :cancelled
      RMX(self).trigger(:cancelled, self)
      RMX(self).trigger(:finished, self)
    end
  end

  # override
  def setup
  end

  def internal_setup
    @api = RMXFirebaseCoordinator.new
    RMXFirebase::QUEUE.barrier_async do
      RMX(@api).on(:finished, :queue => RMXFirebase::QUEUE) do
        RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
        check_ready
      end
      RMX(self).on(:cancelled, :exclusive => [ :ready, :finished ], :queue => :async)
      setup
    end
  end

  def check_ready
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    # p "check_ready cancelled?", @api.cancelled?, dependencies_cancelled.size
    # p "check_ready ready?", @api.ready?, dependencies_ready.size, dependencies.size
    if @api.cancelled? || @dependencies_cancelled.size > 0
      cancelled!
    elsif @api.ready? && @dependencies_ready.size == @dependencies.size
      ready!
    end
  end

  def watch(name, ref, opts={}, &block)
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    RMX(self).ivar(name, @api.watch(name, ref, opts, &block))
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
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
    @dependencies[name] = model
    RMX(self).ivar(name, model)
    track_dependency_state(model)
    RMX(model).on(:finished, :queue => RMXFirebase::QUEUE) do |_model|
      RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
      track_dependency_state(_model)
      check_ready
    end
  end

  def track_dependency_state(model)
    RMX(self).require_queue!(RMXFirebase::QUEUE, __FILE__, __LINE__) if RMX::DEBUG_QUEUES
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
      RMXFirebase.block_on_queue(queue, self, &block)
    end
    RMX(self).on(:ready, :queue => queue, &block)
  end

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

  def once_finished(queue=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      if finished?
        RMXFirebase.block_on_queue(queue, self, &block)
      else
        RMX(self).once(:finished, :strong => true, :queue => queue, &block)
      end
    end
    self
  end

  def cancel_block(&block)
    RMX(self).off(:ready, &block)
    RMX(self).off(:cancelled, &block)
    RMX(self).off(:finished, &block)
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
      if RMXFirebase::DEBUG_IDENTITY_MAP
        p "HIT!", className, opts, existing.retainCount
      end
      return existing
    else
      if RMXFirebase::DEBUG_IDENTITY_MAP
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
    @@identity_map = RMXSynchronizedStrongToWeakHash.new
  end

  def self.identity_map
    @@identity_map
  end

end
