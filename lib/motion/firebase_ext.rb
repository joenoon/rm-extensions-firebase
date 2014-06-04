class Firebase

  DEBUG_SETVALUE = RMExtensions::Env['rmext_firebase_debug_setvalue'] == '1'

  def rmext_object_desc
    "#{super}:#{description}"
  end

  def [](*names)
    if names.length == 0
      childByAutoId
    else
      childByAppendingPath(names.join('/'))
    end
  end

  def limited(limit)
    queryLimitedToNumberOfChildren(limit)
  end

  def starting_at(priority)
    queryStartingAtPriority(priority)
  end

  def ending_at(priority)
    queryEndingAtPriority(priority)
  end

  def rmext_arrayToHash(array)
    hash = {}
    array.each_with_index do |item, i|
      hash[i.to_s] = item
    end
    hash
  end

  def rmext_castValue(value, key=nil)
    if value == true || value == false || value.is_a?(NSString) || value.is_a?(NSNumber)
      # good
    elsif value.nil?
      p "FIREBASE_BAD_TYPE FIXED NIL: #{File.join(*[ description, key ].compact.map(&:to_s))}", "!"
      value = {}
    elsif value.is_a?(Array)
      value = rmext_arrayToHash(value)
      p "FIREBASE_BAD_TYPE FIXED ARRAY: #{File.join(*[ description, key ].compact.map(&:to_s))}: #{value.inspect} (type: #{value.className.to_s})", "!"
    elsif value.is_a?(NSDictionary)
      new_value = {}
      value.keys.each do |k|
        new_value[k.to_s] = rmext_castValue(value[k], k)
      end
      value = new_value
    else
      p "FIREBASE_BAD_TYPE FATAL: #{File.join(*[ description, key ].compact.map(&:to_s))}: #{value.inspect} (type: #{value.className.to_s})", "!"
    end
    # always return the value, corrected or not
    value
  end

  def rmext_setValue(value, andPriority:priority)
    # value = rmext_castValue(value)
    setValue(value, andPriority:priority)
  end
  def rmext_setValue(value)
    # value = rmext_castValue(value)
    setValue(value)
  end
  def rmext_onDisconnectSetValue(value)
    value = rmext_castValue(value)
    onDisconnectSetValue(value)
  end

  alias_method 'orig_setValue', 'setValue'
  alias_method 'orig_setValueAndPriority', 'setValue:andPriority'

  def setValue(value, andPriority:priority)
    if DEBUG_SETVALUE
      p description, "setValue:andPriority", value, priority
    end
    value = rmext_castValue(value)
    orig_setValueAndPriority(value, priority)
  end
  def setValue(value)
    if DEBUG_SETVALUE
      p description, "setValue:", value
    end
    value = rmext_castValue(value)
    orig_setValue(value)
  end

end

class FQuery

  EVENT_TYPES_MAP = {
    :child_added => FEventTypeChildAdded,
    :added => FEventTypeChildAdded,
    :child_moved => FEventTypeChildMoved,
    :moved => FEventTypeChildMoved,
    :child_changed => FEventTypeChildChanged,
    :changed => FEventTypeChildChanged,
    :child_removed => FEventTypeChildRemoved,
    :removed => FEventTypeChildRemoved,
    :value => FEventTypeValue
  }

  def rmext_object_desc
    "#{super}:#{description}"
  end

  def limited(limit)
    queryLimitedToNumberOfChildren(limit)
  end

  def starting_at(priority)
    queryStartingAtPriority(priority)
  end

  def ending_at(priority)
    queryEndingAtPriority(priority)
  end

  HANDLER_SYNC_QUEUE = Dispatch::Queue.new("FirebaseExt.HANDLER_SYNC_QUEUE")

  def on(_event_type, options={}, &and_then)
    and_then = (and_then || options[:completion]).weak!
    raise "event handler is required" unless and_then
    raise "event handler must accept one or two arguments" unless and_then.arity == 1 || and_then.arity == 2

    owner = and_then.owner
    weak_owner = WeakRef.new(owner)
    event_type = EVENT_TYPES_MAP[_event_type]
    raise "event handler is unknown: #{_event_type.inspect}" unless event_type

    disconnect_block = options[:disconnect]
    raise ":disconnect handler must not accept any arguments" if disconnect_block && disconnect_block.arity != 1

    handler = if and_then.arity == 1
      wrapped_block = lambda do |snap|
        if weak_owner.weakref_alive?
          datasnap = FirebaseExt::DataSnapshot.new(snap)
          and_then.call(datasnap)
        end
      end.weak!
      if disconnect_block
        disconnect_block.weak!
        if options[:once]
          observeSingleEventOfType(event_type, withBlock:wrapped_block, withCancelBlock:disconnect_block)
        else
          observeEventType(event_type, withBlock:wrapped_block, withCancelBlock:disconnect_block)
        end
      else
        if options[:once]
          observeSingleEventOfType(event_type, withBlock:wrapped_block)
        else
          observeEventType(event_type, withBlock:wrapped_block)
        end
      end
    else
      wrapped_block = lambda do |snap, prev|
        if weak_owner.weakref_alive?
          datasnap = FirebaseExt::DataSnapshot.new(snap)
          and_then.call(datasnap, prev)
        end
      end.weak!
      if disconnect_block
        disconnect_block.weak!
        if options[:once]
          observeSingleEventOfType(event_type, andPreviousSiblingNameWithBlock:wrapped_block, withCancelBlock:disconnect_block)
        else
          observeEventType(event_type, andPreviousSiblingNameWithBlock:wrapped_block, withCancelBlock:disconnect_block)
        end
      else
        if options[:once]
          observeSingleEventOfType(event_type, andPreviousSiblingNameWithBlock:wrapped_block)
        else
          observeEventType(event_type, andPreviousSiblingNameWithBlock:wrapped_block)
        end
      end
    end
    unless options[:once]
      HANDLER_SYNC_QUEUE.sync do
        unless @_outstanding_handlers
          @_outstanding_handlers = OutstandingHandlers.new(self)
        end
        @_outstanding_handlers << handler
      end
    end
    handler
  end

  class OutstandingHandlers

    def initialize(scope)
      @scope = WeakRef.new(scope)
      @handlers = []
    end

    def <<(handler)
      @handlers << handler
    end

    def handlers
      @handlers
    end

    def off(handle=nil)
      if @scope.weakref_alive?
        if _handle = @handlers.delete(handle)
          # p @scope.rmext_object_desc, "remove handle", _handle
          @scope.removeObserverWithHandle(_handle)
        else
          _handlers = @handlers.dup
          while _handlers.size > 0
            _handle = _handlers.shift
            off(_handle)
          end
        end
      end
    end

    def dealloc
      off
      super
    end
  end

  def once(event_type, options={}, &and_then)
    on(event_type, options.merge(:once => true), &and_then)
  end

  def _off(handle)
    if @_outstanding_handlers
      @_outstanding_handlers.off(handle)
    end
    self
  end

  def off(handle)
    HANDLER_SYNC_QUEUE.sync do
      _off(handle)
    end
    self
  end

  def description
    AFHTTPRequestSerializer.serializer.requestWithMethod("GET", URLString: "https://#{repo.repoInfo.host}#{path.toString}", parameters:queryParams.queryObject).URL.absoluteString
  end

end

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

  def self.block_on_queue(queue, block, *args)
    queue = queue_for(queue)
    unless block.nil?
      if NSThread.currentThread.isMainThread && queue == Dispatch::Queue.main
        block.call(*args)
      else
        queue.barrier_async do
          block.call(*args)
        end
      end
    end
  end

  class DataSnapshot

    include RMExtensions::CommonMethods

    attr_accessor :snap

    def initialize(snap)
      @snap = snap
    end

    def hasValue?
      !value.nil?
    end

    def attr(keypath)
      valueForKeyPath(keypath)
    end

    def valueForKey(key)
      if v = value
        v[key]
      end
    end

    def valueForUndefinedKey(key)
      nil
    end

    def value
      snap.retain.autorelease.value
    end

    def ref
      snap.retain.autorelease.ref
    end

    def name
      snap.retain.autorelease.name
    end

    def priority
      snap.retain.autorelease.priority
    end

    def count
      snap.retain.autorelease.childrenCount
    end

    def children
      snap.retain.autorelease.children.each.map { |x| DataSnapshot.new(x) }
    end

  end

  class Listener

    include RMExtensions::CommonMethods

    attr_accessor :snapshot, :ref, :callback, :handle, :value_required
    rmext_weak_attr_accessor :callback_owner

    def rmext_dealloc
      if ref && handle
        ref.off(handle)
      end
    end

    def ready?
      !!@ready
    end

    def cancelled?
      !!@cancelled
    end

    def start!
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      weak_self = WeakRef.new(self)
      cancel_block = lambda do |err|
        if weak_self.weakref_alive?
          @cancelled = err
          rmext_trigger(:cancelled, self)
          rmext_trigger(:finished, self)
        end
      end
      @handle = ref.on(:value, { :disconnect => cancel_block }) do |snap|
        QUEUE.barrier_async do
          @snapshot = snap
          if value_required && !snap.hasValue?
            cancel_block.call(NSError.errorWithDomain("requirement failure", code:0, userInfo:{
              :error => "requirement_failure"
            }))
          else
            callback.call(snap) if callback && callback_owner
            @ready = true
            rmext_trigger(:ready, self)
            rmext_trigger(:finished, self)
            # p "ready__"
          end
        end
      end
    end

    def stop!
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      @cancelled = false
      @ready = false
      if ref && handle
        ref.off(handle)
      end
    end

    def hasValue?
      !!(snapshot && snapshot.hasValue?)
    end

    def toValue
      snapshot && snapshot.value
    end

    def attr(keypath)
      valueForKeyPath(keypath)
    end

    def valueForKey(key)
      snapshot && snapshot.valueForKey(key)
    end

    def valueForUndefinedKey(key)
      nil
    end

  end

  class Coordinator

    include RMExtensions::CommonMethods

    def watches
      unless @watches
        @watches = {}
      end
      @watches
    end

    def clear!
      QUEUE.barrier_async do
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
      QUEUE.barrier_async do
        @ready = true
        rmext_trigger(:ready, self)
        rmext_trigger(:finished, self)
      end
    end

    def cancelled!
      QUEUE.barrier_async do
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

  class Model
    
    include RMExtensions::CommonMethods

    attr_accessor :opts

    attr_reader :api, :root

    def initialize(opts=nil)
      @opts = opts
      QUEUE.barrier_async do
        internal_setup
      end
    end

    def dependencies_cancelled
      unless @dependencies_cancelled
        @dependencies_cancelled = {}
      end
      @dependencies_cancelled
    end

    def dependencies_ready
      unless @dependencies_ready
        @dependencies_ready = {}
      end
      @dependencies_ready
    end

    def dependencies
      unless @dependencies
        @dependencies = {}
      end
      @dependencies
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
      QUEUE.barrier_async do
        # p "ready!"
        @ready = true
        rmext_trigger(:ready, self)
        rmext_trigger(:finished, self)
      end
    end

    def cancelled!
      QUEUE.barrier_async do
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
      setup
    end

    def check_ready
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      # p "check_ready cancelled?", @api.cancelled?, dependencies_cancelled.size
      # p "check_ready ready?", @api.ready?, dependencies_ready.size, dependencies.size
      if @api.cancelled? || dependencies_cancelled.size > 0
        cancelled!
      elsif @api.ready? && dependencies_ready.size == dependencies.size
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
      dependencies[name] = model
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
        dependencies_ready[model] = true
        dependencies_cancelled.delete(model)
      elsif model.cancelled?
        dependencies_cancelled[model] = true
        dependencies_ready.delete(model)
      end
    end

    def always_async(&block)
      always(:async, &block)
    end

    def always(queue=nil, &block)
      return false if cancelled?
      start_time = if DEBUG_FIREBASE_TIMING
        Time.now
      end
      if ready?
        FirebaseExt.block_on_queue(queue, block, self)
      end
      # return an unbinder
      block.weak!
      rmext_on(:ready, :queue => queue, &block)
      if DEBUG_FIREBASE_TIMING
        rmext_on(:ready, :queue => queue) do
          p "ALWAYS #{rmext_object_desc}: #{Time.now - start_time}"
        end
      end
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:ready, &block)
        end
      end
      rmext_once(:cancelled, :queue => queue, &unbinder)
      unbinder
    end

    # Model
    def once(queue=nil, &block)
      QUEUE.barrier_async do
        retain
        block.owner.retain
        if ready? || cancelled?
          FirebaseExt.block_on_queue(queue, block, self)
          autorelease
          block.owner.autorelease
        else
          rmext_once(:ready, :queue => queue, &block)
          rmext_once(:finished, :queue => queue) do
            autorelease
            block.owner.autorelease
          end
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

  class Batch

    include RMExtensions::CommonMethods

    def models
      unless @models
        @models = []
      end
      @models
    end

    def ready_models
      unless @ready_models
        @ready_models = []
      end
      @ready_models
    end

    def initialize(*models)
      _models = models.flatten.compact.dup
      QUEUE.barrier_async do
        setup_models(_models)
      end
    end

    def complete_blocks
      unless @complete_blocks
        @complete_blocks = {}
      end
      @complete_blocks
    end

    def setup_models(the_models)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      @ready = false
      @models = the_models.dup
      @ready_count = 0
      @pending_count = models.size
      if models.any?
        _models = models.dup
        _pairs = []
        i = 0
        while _models.size > 0
          ii = i # strange: proc doesnt seem to close over i correctly
          model = _models.shift
          blk = proc do
            rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
            # p "COMPLETE!", ii, model
            complete_blocks.delete(model)
            ready_models[ii] = model
            @ready_count += 1
            @pending_count -= 1
            if @pending_count == 0
              ready!
            end
          end
          complete_blocks[model] = blk
          _pairs << [ model, blk ]
          i += 1
        end
        QUEUE.barrier_async do
          while pair = _pairs.shift
            pair[0].once(QUEUE, &pair[1])
          end
        end
      else
        QUEUE.barrier_async do
          ready!
        end
      end
    end

    def ready!
      QUEUE.barrier_async do
        @ready = true
        # p "models", models.dup
        # p "ready_models", ready_models.dup
        rmext_trigger(:ready, ready_models.dup)
      end
    end

    def cancel!
      QUEUE.barrier_async do
        models_outstanding = complete_blocks.keys.dup
        while models_outstanding.size > 0
          model = models_outstanding.shift
          if blk = complete_blocks[model]
            complete_blocks.delete(model)
            model.cancel_block(&blk)
          end
        end
      end
    end

    def ready?
      !!@ready
    end

    # Batch
    def once(queue=nil, &block)
      QUEUE.barrier_async do
        retain
        block.owner.retain
        start_time = if DEBUG_FIREBASE_TIMING
          Time.now
        end
        if ready?
          FirebaseExt.block_on_queue(queue, block, ready_models.dup)
          autorelease
          block.owner.autorelease
        else
          rmext_once(:ready, :queue => queue, &block)
          rmext_once(:ready, :queue => queue) do
            autorelease
            block.owner.autorelease
          end
          if DEBUG_FIREBASE_TIMING
            rmext_once(:ready, :queue => queue) do |_models|
              p "BATCH ONCE #{_models.size} like `#{_models.first.rmext_object_desc}`: #{Time.now - start_time}"
            end
          end
        end
      end
      self
    end

    def cancel_block(&block)
      rmext_off(:ready, &block)
    end

  end

  class Collection

    include RMExtensions::CommonMethods

    attr_reader :ref

    # public
    def ready?
      !!@ready
    end

    # public
    def cancelled?
      !!@cancelled
    end

    # overridable
    def transform(snap)
      if block = @transform_block
        if @transform_block_weak_owner.weakref_alive?
          block.call(snap)
        end
      else
        snap
      end
    end

    def transformed_async(&block)
      transformed(:async, &block)
    end

    # public, completes with ready transformations
    def transformed(queue=nil, &block)
      items = transformations.dup
      if (snap = items.first) && snap.is_a?(Model)
        FirebaseExt::Batch.new(items).once(queue, &block)
      else
        FirebaseExt.block_on_queue(queue, block, items)
      end
      self
    end

    def once_async(&block)
      once(:async, &block)
    end

    # Collection
    # completes with `self` once, when the collection is ready.
    # retains `self` and the sender until complete
    def once(queue=nil, &block)
      QUEUE.barrier_async do
        retain
        block.owner.retain
        if ready?
          FirebaseExt.block_on_queue(queue, block, self)
          autorelease
          block.owner.autorelease
        else
          rmext_once(:ready, :queue => queue, &block)
          rmext_once(:finished, :queue => queue) do
            autorelease
            block.owner.autorelease
          end
        end
      end
      self
    end

    def always_async(&block)
      always(:async, &block)
    end

    # completes with `self` immediately if ready, and every time the collection :ready fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def always(queue=nil, &block)
      return false if cancelled?
      start_time = if DEBUG_FIREBASE_TIMING
        Time.now
      end
      if ready?
        FirebaseExt.block_on_queue(queue, block, self)
      end
      # return an unbinder
      block.weak!
      rmext_on(:ready, :queue => queue, &block)
      if DEBUG_FIREBASE_TIMING
        rmext_on(:ready, :queue => queue) do
          p "ALWAYS #{rmext_object_desc} #{ref.description}: #{Time.now - start_time}"
        end
      end
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:ready, &block)
        end
      end
      rmext_once(:cancelled, :queue => queue, &unbinder)
      unbinder
    end

    # completes with `self` every time the collection :changed fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def changed(queue=nil, &block)
      return false if cancelled?
      # return an unbinder
      block.weak!
      rmext_on(:changed, :queue => queue, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:changed, &block)
        end
      end
      rmext_once(:cancelled, :queue => queue, &unbinder)
      unbinder
    end

    # completes with `self`, `snap`, `prev` every time the collection :added fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def added(queue=nil, &block)
      return false if cancelled?
      # return an unbinder
      block.weak!
      rmext_on(:added, :queue => queue, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:added, &block)
        end
      end
      rmext_once(:cancelled, :queue => queue, &unbinder)
      unbinder
    end

    # completes with `self`, `snap` every time the collection :removed fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def removed(queue=nil, &block)
      return false if cancelled?
      # return an unbinder
      block.weak!
      rmext_on(:removed, :queue => queue, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:removed, &block)
        end
      end
      rmext_once(:cancelled, :queue => queue, &unbinder)
      unbinder
    end

    # completes with `self`, `snap`, `prev` every time the collection :moved fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def moved(queue=nil, &block)
      return false if cancelled?
      # return an unbinder
      block.weak!
      rmext_on(:moved, :queue => queue, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:moved, &block)
        end
      end
      rmext_once(:cancelled, :queue => queue, &unbinder)
      unbinder
    end

    # internal
    def initialize(ref)
      QUEUE.barrier_async do
        setup_ref(ref)
      end
    end

    def snaps_by_name
      unless @snaps_by_name
        @snaps_by_name = {}
      end
      @snaps_by_name
    end

    def snaps
      unless @snaps
        @snaps = []
      end
      @snaps

    end

    def transformations_table
      unless @transformations_table
        @transformations_table = {}
      end
      @transformations_table
    end

    def transformations
      unless @transformations
        @transformations = []
      end
      @transformations
    end

    # internal
    def setup_ref(_ref)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      _clear_current_ref!
      @ref = _ref
      @ready = false
      @cancelled = false
      weak_self = WeakRef.new(self)
      cancel_block = lambda do |err|
        if weak_self.weakref_alive?
          @cancelled = err
          cancelled!
        end
      end
      @added_handler = @ref.on(:added) do |snap, prev|
        # p "NORMAL ", snap.name, prev
        QUEUE.barrier_async do
          # p "BARRIER", snap.name, prev
          add(snap, prev)
        end
      end
      @removed_handler = @ref.on(:removed) do |snap|
        QUEUE.barrier_async do
          remove(snap)
        end
      end
      @moved_handler = @ref.on(:moved) do |snap, prev|
        QUEUE.barrier_async do
          add(snap, prev)
        end
      end
      @value_handler = @ref.once(:value, { :disconnect => cancel_block }) do |collection|
        @value_handler = nil
        QUEUE.barrier_async do
          ready!
        end
      end
    end

    def refresh_order!
      QUEUE.barrier_async do
        next unless @ref
        if @added_handler
          @ref.off(@added_handler)
          @added_handler = nil
        end
        @added_handler = @ref.on(:added) do |snap, prev|
          # p "NORMAL ", snap.name, prev
          QUEUE.barrier_async do
            # p "BARRIER", snap.name, prev
            add(snap, prev)
          end
        end
      end
    end

    # mess up the order on purpose
    def _test_scatter!
      QUEUE.barrier_async do
        _snaps = @snaps.dup
        p "before scatter", @snaps.map(&:name)
        p "before scatter snaps_by_name", @snaps_by_name

        _snaps.each do |snap|
          others = _snaps - [ snap ]
          random = others.sample
          add(snap, random.name)
        end
      end
    end

    def rmext_dealloc
      _clear_current_ref!
    end

    def _clear_current_ref!
      if @ref
        if @added_handler
          @ref.off(@added_handler)
          @added_handler = nil
        end
        if @removed_handler
          @ref.off(@removed_handler)
          @removed_handler = nil
        end
        if @moved_handler
          @ref.off(@moved_handler)
          @moved_handler = nil
        end
        if @value_handler
          @ref.off(@value_handler)
          @value_handler = nil
        end
        @ref = nil
      end
    end


    # internal
    def ready!
      QUEUE.barrier_async do
        @ready = true
        rmext_trigger(:ready, self)
        rmext_trigger(:changed, self)
        rmext_trigger(:finished, self)
      end
    end

    # internal
    def cancelled!
      QUEUE.barrier_async do
        @cancelled = true
        rmext_trigger(:cancelled, self)
        rmext_trigger(:finished, self)
      end
    end

    # internal, allows the user to pass a block for transformations instead of subclassing
    # and overriding #transform, for one-off cases
    def transform=(block)
      if block
        @transform_block_weak_owner = WeakRef.new(block.owner)
        @transform_block = block.weak!
      else
        @transform_block_weak_owner = nil
        @transform_block = nil
      end
    end

    # internal
    def store_transform(snap)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      transformations_table[snap] ||= transform(snap)
    end

    def _log_snap_names
      QUEUE.barrier_sync do
        puts "snaps_by_name:"
        _log_hash(snaps_by_name)
      end
    end


    def _log_hash(hash)
      hash.to_a.sort_by { |x| x[1] }.each do |pair|
        puts pair.inspect
      end
    end

    # internal
    def add(snap, prev)
      rmext_require_queue!(QUEUE, __FILE__, __LINE__) if RMExtensions::DEBUG_QUEUES
      moved = false

      if current_index = snaps_by_name[snap.name]
        if current_index == 0 && prev.nil?
          return
        elsif current_index > 0 && prev && snaps_by_name[prev] == current_index - 1
          return
        end
        moved = true
        snaps.delete_at(current_index)
        transformations.delete_at(current_index)
        if was_index = snaps_by_name.delete(snap.name)
          snaps_by_name.keys.each do |k|
            v = snaps_by_name[k]
            if v > was_index
              snaps_by_name[k] -= 1
            end
          end
        end
        # raise if snaps_by_name.values.uniq.size != snaps_by_name.values.size
      end
      # raise if snaps_by_name.values.uniq.size != snaps_by_name.values.size
      if prev && (index = snaps_by_name[prev])
        new_index = index + 1
        snaps.insert(new_index, snap)
        transformations.insert(new_index, store_transform(snap))
        snaps_by_name.keys.each do |k|
          v = snaps_by_name[k]
          if v >= new_index
            snaps_by_name[k] += 1
          end
        end
        snaps_by_name[snap.name] = new_index
        # raise if snaps_by_name.values.uniq.size != snaps_by_name.values.size
      else
        snaps.unshift(snap)
        transformations.unshift(store_transform(snap))
        snaps_by_name.keys.each do |k|
          v = snaps_by_name[k]
          snaps_by_name[k] += 1
        end
        snaps_by_name[snap.name] = 0
        # raise if snaps_by_name.values.uniq.size != snaps_by_name.values.size
      end
      if moved
        rmext_trigger(:moved, self, snap, prev)
      else
        rmext_trigger(:added, self, snap, prev)
      end
      rmext_trigger(:changed, self)
      if ready?
        rmext_trigger(:ready, self)
        rmext_trigger(:finished, self)
      end
    end

    # internal
    def remove(snap)
      if current_index = snaps_by_name[snap.name]
        snaps.delete_at(current_index)
        transformations.delete_at(current_index)
        snaps_by_name.keys.each do |k|
          v = snaps_by_name[k]
          if v > current_index
            snaps_by_name[k] -= 1
          end
        end
        rmext_trigger(:removed, self, snap)
        rmext_trigger(:changed, self)
        if ready?
          rmext_trigger(:ready, self)
          rmext_trigger(:finished, self)
        end
      end
    end

    # this is the method you should call
    def self.get(ref)
      if ref && existing = identity_map[[ className, ref.description ]]
        if DEBUG_IDENTITY_MAP
          p "HIT!", className, ref.description, existing.retainCount
        end
        return existing
      else
        if DEBUG_IDENTITY_MAP
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
      @@identity_map = RMExtensions::IdentityMap.new
    end

    def self.identity_map
      @@identity_map
    end

  end

  module HandleModel
    def handle(key)
      define_method(key) do
        model
      end
      define_method("#{key}=") do |val|
        self.model = val
      end
    end
  end

  class TableViewCell < ::RMExtensions::TableViewCell

    extend HandleModel

    def prepareForReuse
      if @data
        @data_unbinder.call if @data_unbinder
        @data_unbinder = nil
      end
      @data = nil
      reset
    end

    def reset
    end

    def changed
    end

    def data=(val)
      return @data if val == @data
      @data = val
      if @data
        unless @data.ready?
          raise "#{className} tried to use a model that is not ready: #{@data.inspect}"
        end
        @data_unbinder = @data.always do |m|
          next unless m == @data
          changed
        end
      end
      @data
    end

    def model
      @data
    end

    def model=(val)
      self.data = val
    end

  end

  class View < ::RMExtensions::View

    extend HandleModel

    def reset
    end

    def changed
    end

    def model
      @model
    end

    def model=(val)
      return @model if @model == val
      if @model
        @model_unbinder.call if @model_unbinder
        @model_unbinder = nil
      end
      @model = val
      reset
      if @model
        unless @model.ready?
          raise "#{className} tried to use a model that is not ready: #{@model.rmext_object_desc}"
        end
        @model_unbinder = @model.always do |m|
          next unless m == @model
          changed
        end
      end
      @model
    end

  end

  class ViewController < ::RMExtensions::ViewController

    extend HandleModel

    def viewDidLoad
      s = super
      if @pending_changed
        @pending_changed = nil
        if @model
          changed
        end
      end
      s
    end

    def changed
    end

    def model
      @model
    end

    def model=(val)
      return @model if @model == val
      if @model
        @model_unbinder.call if @model_unbinder
        @model_unbinder = nil
      end
      @model = val
      if @model
        unless @model.ready?
          raise "#{className} tried to use a model that is not ready: #{@model.inspect}"
        end
        @model_unbinder = @model.always do |m|
          next unless m == @model
          if isViewLoaded
            changed
          else
            @pending_changed = true
          end
        end
      end
      @model
    end

  end
  
end
