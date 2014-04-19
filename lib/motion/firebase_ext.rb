class Firebase
  def [](*names)
    if names.length == 0
      childByAutoId
    else
      childByAppendingPath(names.join('/'))
    end
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

  class Holder
    
    attr_accessor :map
    
    def initialize
      @map = NSMapTable.weakToStrongObjectsMapTable
      @own = NSMapTable.weakToStrongObjectsMapTable
    end

    def own_snapshot(snap)
      ref = snap.ref
      unless owned = @own.objectForKey(ref)
        owned = []
        @own.setObject(owned, forKey:ref)
      end
      owned.push snap
    end

    def track(fquery, handler, leaf)
      unless query_handles = @map.objectForKey(leaf)
        query_handles = {}
        @map.setObject(query_handles, forKey:leaf)
      end
      query_handles[handler] = fquery
    end

    def off(handle=nil, cleanup_only=false)
      object_context = !handle.is_a?(Integer) && handle
      handle = nil if object_context
      keyEnum = @map.keyEnumerator
      keys = []
      while key = keyEnum.nextObject
        keys.push key
      end
      while other = keys.pop
        next if object_context && other != object_context
        if hash = @map.objectForKey(other)
          hash_keys = [] + hash.keys
          while handler = hash_keys.pop
            if !handle || handler == handle
              fquery = hash[handler]
              @own.removeObjectForKey(fquery)
              hash.delete(handler)
              unless cleanup_only
                # p fquery, "removeObserverWithHandle", handler
                fquery.removeObserverWithHandle(handler)
              end
              other_handlers = other.instance_variable_get("@_firebase_handlers")
              other_handlers.off(handler, true)
            end
          end
        end
      end
    end
    def dealloc
      off
      super
    end
  end

  def ensure_firebase_handlers(object)
    unless _firebase_handlers = object.instance_variable_get("@_firebase_handlers")
      _firebase_handlers = object.instance_variable_set("@_firebase_handlers", Holder.new)
    end
    _firebase_handlers
  end

  def own_snapshot(object, snap)
    _firebase_handlers = ensure_firebase_handlers(object)
    _firebase_handlers.own_snapshot(snap)
    nil
  end

  def track_handler(object, handler, leaf)
    _firebase_handlers = ensure_firebase_handlers(object)
    _firebase_handlers.track(self, handler, leaf)
    nil
  end

  Dispatch.once do
    $firebase_masters_by_url = NSMapTable.strongToWeakObjectsMapTable
    $firebase_masters_by_fquery = NSMapTable.weakToWeakObjectsMapTable
  end

  def print_masters
    puts "$firebase_masters_by_url:"
    for k in $firebase_masters_by_url.keyEnumerator
      puts "  - #{k}: #{$firebase_masters_by_url.objectForKey(k).rmext_object_desc}"
    end
    puts "$firebase_masters_by_fquery:"
    for k in $firebase_masters_by_fquery.keyEnumerator
      puts "  - #{k.rmext_object_desc}: #{$firebase_masters_by_fquery.objectForKey(k).rmext_object_desc}"
    end
    nil
  end

  def master
    if m = $firebase_masters_by_url.objectForKey(description)
      m
    else
      $firebase_masters_by_url.setObject(self, forKey:description)
      self
    end
  end

  def on(event_type, options={}, &and_then)
    master._on(event_type, options, &and_then)
  end

  def _on(_event_type, options={}, &and_then)
    and_then = (and_then || options[:completion]).weak!
    raise "event handler is required" unless and_then
    raise "event handler must accept one or two arguments" unless and_then.arity == 1 || and_then.arity == 2

    owner = and_then.owner
    weak_owner = WeakRef.new(owner)
    event_type = EVENT_TYPES_MAP[_event_type]
    raise "event handler is unknown: #{_event_type.inspect}" unless event_type
    if event_type == FEventTypeValue
      if initial_snap = $firebase_masters_by_fquery.objectForKey(self)
        # p "HIT!", description
        rmext_inline_or_on_main_q do
          and_then.call(initial_snap)
        end
      else
        # p "MISS!", description
      end
    end

    disconnect_block = options[:disconnect]
    raise ":disconnect handler must not accept any arguments" if disconnect_block && disconnect_block.arity > 0

    handler = if and_then.arity == 1
      wrapped_block = lambda do |snap|
        $firebase_masters_by_fquery.setObject(snap, forKey:self)
        own_snapshot(weak_owner, snap) if weak_owner.weakref_alive?
        and_then.call(snap)
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
        $firebase_masters_by_fquery.setObject(snap, forKey:self)
        and_then.call(snap, prev)
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
    track_handler(owner, handler, self)
    track_handler(self, handler, owner)
    handler
  end

  def once(event_type, options={}, &and_then)
    on(event_type, options.merge(:once => true), &and_then)
  end

  def off(handle=nil)
    master._off(handle)
  end

  def _off(handle=nil)
    if @_firebase_handlers
      @_firebase_handlers.off(handle)
    else
      @_firebase_handlers.off
    end
    return self
  end

  def self.off_context(owner, handle=nil)
    if _firebase_handlers = owner.instance_variable_get("@_firebase_handlers")
      _firebase_handlers.off(handle)
    end
  end

  def description
    AFHTTPRequestSerializer.serializer.requestWithMethod("GET", URLString: "https://#{repo.repoInfo.host}#{path.toString}", parameters:queryParams.queryObject).URL.absoluteString
  end

end

module FirebaseExt

  class DataSnapshot

    include RMExtensions::CommonMethods

    attr_accessor :value, :ref, :callback, :handle

    def dealloc
      dealloc_inspect
      super
    end

    def ready?
      !!@ready
    end

    def start!
      self.handle = ref.on(:value) do |snap|
        self.value = snap.value
        @ready = true
        rmext_trigger(:ready)
        # p "ready__"
        @callback.call if @callback
      end
    end

    def stop!
      if ref && handle
        ref.off(handle)
      end
    end

    def [](*keys)
      current = value
      keys.each do |key|
        current = current && current[key]
      end
      current
    end

  end

  class Coordinator

    include RMExtensions::CommonMethods

    def dealloc
      dealloc_inspect
      super
    end

    def initialize
      @watches = {}
    end

    def ready?
      !!@ready
    end

    def ready!
      @ready = true
      rmext_trigger(:ready)
    end

    def stub(name)
      @watches[name] ||= DataSnapshot.new
    end

    def watch(name, ref, &block)
      data = DataSnapshot.new
      data.ref = ref
      data.callback = block && RMExtensions::WeakBlock.new(block)
      data.rmext_on(:ready) do
        if @watches.values.all?(&:ready?)
          ready!
          # p "ready__"
        end
      end
      data.start!
      if current = @watches[name]
        current.stop!
      end
      @watches[name] = data
      data
    end

    def [](*keys)
      name = keys.shift
      res = @watches[name]
      if res
        if keys.size.zero?
          res
        else
          res[*keys]
        end
      end
    end

    def []=(*keys, val)
      p "[]=", keys, val
      name = keys.shift
      res = @watches[name]
      ref = if res
        if keys.size.zero?
          res.ref
        else
          res.ref[*keys]
        end
      end
      if ref
        if val.is_a?(Hash)
          ref.updateChildValues(val)
        else
          ref.setValue(val)
        end
      end
    end

  end

  class Model
    
    include RMExtensions::CommonMethods

    def dealloc
      dealloc_inspect
      super
    end

    attr_accessor :opts, :shortcuts

    def initialize(opts=nil)
      @shortcuts = {}
      @opts = opts
      setup
    end

    def ready?
      !!@ready
    end

    def ready!
      @ready = true
      rmext_trigger(:ready)
    end

    def setup
      rmext_cleanup
      @api = Coordinator.new
      @api.rmext_on(:ready) do
        ready!
      end
      if block = self.class.describe_block
        block.call(self, @opts)
      end
    end

    def watch(name, ref, &block)
      @api.watch(name, ref, &block)
    end

    def ivar_key
      "firebasemodel_#{object_id}_readyblk"
    end

    def unbind_ready(context)
      if existing = context.rmext_ivar(ivar_key)
        rmext_off(:ready, self, &existing)
      end
    end

    def ready(&block)
      unbind_ready(block.owner)
      block.weak!
      block.owner.rmext_ivar(ivar_key, block)
      rmext_on(:ready, &block)
      if ready?
        block.call
      end
      self
    end

    def ready_once(&block)
      if ready?
        block.call
      else
        rmext_on(:ready, &block)
      end
      self
    end

    def cancel_ready(&block)
      rmext_off(:ready, &block)
    end

    def [](*keys)
      if keys.first && long = (@shortcuts[keys.first.to_sym] || @shortcuts[keys.first.to_s])
        keys = long
      end
      @api[*keys]
    end

    def []=(*keys, val)
      # p "[]=", keys, val
      if keys.first && long = (@shortcuts[keys.first.to_sym] || @shortcuts[keys.first.to_s])
        keys = long
      end
      @api[*keys] = val
    end

    def self.create(&block)
      x = new
      block.call(x)
      x
    end

    def self.describe(&block)
      @describe_block = block
    end

    def self.describe_block
      @describe_block
    end

    # this is the method you should call
    def self.get(opts=nil)
      if opts && existing = get_in_memory(opts)
        # p "HIT!", opts
        return existing
      else
        # p "MISS!", opts
        res = new(opts)
        if opts
          set_in_memory(opts, res)
        end
        res
      end
    end

    def self.set_in_memory(key, val)
      return unless key
      key = [ className, key ]
      memory_queue.sync do
        unless memory.objectForKey(key)
          memory.setObject(val, forKey:key)
        end
      end
      nil
    end

    def self.get_in_memory(key)
      return unless key
      key = [ className, key ]
      memory_queue.sync do
        return memory.objectForKey(key)
      end
    end

    def self.memory_queue
      ::FirebaseExt::Model::Memory.memory_queue
    end

    def self.memory
      ::FirebaseExt::Model::Memory.memory
    end

    module Memory
      extend self

      def memory
        Dispatch.once do
          # stores objects in memory, to form an identity map, so the same
          # object (by key) is not instantiated twice.
          @memory = NSMapTable.strongToWeakObjectsMapTable
        end
        @memory
      end

      def memory_queue
        Dispatch.once do
          # a queue which all access to @memory will use
          @memory_queue = Dispatch::Queue.new("#{NSBundle.mainBundle.bundleIdentifier}.FirebaseExt.Model.memory")
        end
        @memory_queue
      end

    end

  end

  class Batch

    include RMExtensions::CommonMethods

    attr_accessor :models

    def dealloc
      dealloc_inspect
      super
    end

    def initialize(*models)
      @ready = false
      @models = models.flatten
      @complete_blocks = {}
      @models.each do |model|
        @complete_blocks[model] = proc do
          # p "COMPLETE!"
          @complete_blocks.delete(model)
          if @complete_blocks.empty?
            ready!
          end
        end
      end
      @complete_blocks.each_pair do |model, block|
        model.ready_once(&block)
      end
    end

    def ready!
      @ready = true
      rmext_trigger(:ready)
    end

    def cancel!
      models_outstanding = @complete_blocks.keys.dup
      while model = models_outstanding.pop
        if blk = @complete_blocks[model]
          @complete_blocks.delete(model)
          model.cancel_ready(&blk)
        end
      end
    end

    def ready?
      !!@ready
    end

    def ready_once(&block)
      if ready?
        block.call
      else
        rmext_once(:ready, &block)
      end
      self
    end

    def cancel_ready(&block)
      rmext_off(:ready, &block)
    end

  end

  class TableViewCell < ::RMExtensions::TableViewCell

    def prepareForReuse
      if @data
        @data.unbind_ready(self)
      end
      @data = nil
      reset
    end

    def reset
    end

    def ready(model)
    end

    def data=(val)
      @data = val
      if @data
        @data.ready do
          ready(@data)
        end
      end
      @data
    end

  end

  class View < ::RMExtensions::View

    attr_reader :model

    def reset
    end

    def ready(model)
    end

    def model=(val)
      if @model
        @model.unbind_ready(self)
      end
      @model = val
      reset
      if @model
        @model.ready do
          ready(@model)
        end
      end
      @model
    end

  end

  class ViewController < ::RMExtensions::ViewController

    attr_reader :model

    def ready(model)
    end

    def model=(val)
      if @model
        @model.unbind_ready(self)
      end
      @model = val
      if @model
        @model.ready do
          ready(@model)
        end
      end
      @model
    end

  end
  
end
