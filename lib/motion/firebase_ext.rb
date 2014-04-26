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
                # p fquery, "removeObserverWithHandle", handler, caller
                fquery.removeObserverWithHandle(handler)
              end
              other_handlers = other.instance_variable_get("@_firebase_handlers")
              other_handlers.off(handler, true)
            end
          end
        end
      end
      nil
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
    # if event_type == FEventTypeValue
    #   if initial_snap = $firebase_masters_by_fquery.objectForKey(self)
    #     # p "HIT!", description
    #     rmext_inline_or_on_main_q do
    #       and_then.call(initial_snap)
    #     end
    #   else
    #     # p "MISS!", description
    #   end
    # end

    disconnect_block = options[:disconnect]
    raise ":disconnect handler must not accept any arguments" if disconnect_block && disconnect_block.arity > 0

    handler = if and_then.arity == 1
      wrapped_block = lambda do |snap|
        if weak_owner.weakref_alive?
          datasnap = FirebaseExt::DataSnapshot.new(snap)
          $firebase_masters_by_fquery.setObject(datasnap, forKey:self)
          own_snapshot(weak_owner, datasnap)
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
          $firebase_masters_by_fquery.setObject(datasnap, forKey:self)
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
      track_handler(owner, handler, self)
      track_handler(self, handler, owner)
      handler
    end
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

    attr_accessor :value, :ref, :name

    def dealloc
      dealloc_inspect
      super
    end

    def initialize(snap=nil)
      if snap
        @snap = snap
        @ref = snap.ref
        @name = snap.name
        @value = snap.value
      end
    end

    def hasValue?
      !value.nil?
    end

    def attr(keypath)
      valueForKeyPath(keypath)
    end

    def valueForKey(key)
      value && value[key]
    end

    def valueForUndefinedKey(key)
      nil
    end

  end

  class Listener

    include RMExtensions::CommonMethods

    attr_accessor :snapshot, :ref, :callback, :handle

    def dealloc
      dealloc_inspect
      stop!
      super
    end

    def ready?
      !!@ready
    end

    def start!
      cancel_block = lambda do
        p "cancel block"
        raise "unhandled cancel"
      end
      @handle = ref.on(:value, { :disconnect => cancel_block }) do |snap|
        @snapshot = snap
        @callback.call(snap) if @callback
        @ready = true
        rmext_trigger2(:ready, self)
        # p "ready__"
      end
    end

    def stop!
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

    attr_accessor :watches

    def dealloc
      dealloc_inspect
      super
    end

    def clear!
      @ready = false
      keys = @watches.keys.dup
      while name = keys.pop
        watch = @watches[name]
        watch.stop!
      end
      @watches.clear
      self
    end

    def initialize
      @watches = {}
    end

    def ready?
      !!@ready
    end

    def ready!
      @ready = true
      rmext_trigger2(:ready, self)
    end

    def stub(name)
      @watches[name] ||= Listener.new
    end

    def watch_data(name, data)
      if current = @watches[name]
        if current == data || current.description == data.description
          return
        end
        current.stop!
        current.rmext_off(:ready, self)
      end
      data.rmext_on(:ready) do
        if @watches.values.all?(&:ready?)
          ready!
          # p "ready__"
        end
      end
      @watches[name] = data
    end

    def watch(name, ref, &block)
      data = Listener.new
      data.ref = ref
      data.callback = block && RMExtensions::WeakBlock.new(block)
      watch_data(name, data)
      data.start!
      data
    end

    def attr(keypath)
      valueForKeyPath(keypath)
    end

    def valueForKey(key)
      @watches[key]
    end

    def valueForUndefinedKey(key)
      nil
    end

  end

  class Model
    
    include RMExtensions::CommonMethods

    def dealloc
      dealloc_inspect
      super
    end

    attr_accessor :opts

    attr_reader :api, :root

    def initialize(opts=nil)
      @opts = opts
      internal_setup
    end

    def ready?
      !!@ready
    end

    def ready!
      @ready = true
      rmext_trigger2(:ready, self)
      @waiting_once = nil
    end

    # override
    def setup(opts=nil)
    end

    def internal_setup
      rmext_cleanup
      @api = Coordinator.new
      @api.rmext_on(:ready) do
        self.ready!
      end
      setup(@opts)
    end

    def reload
      @ready = false
      old_watches = @api.watches # keep them in memory momentarily
      internal_setup
      old_watches = nil # let them go
      self
    end

    def watch(name, ref, &block)
      rmext_ivar(name, @api.watch(name, ref, &block))
    end

    # combine the watches of another model into this model,
    # which will affect ready.  should be done before ready has
    # has a chance to be triggered.  inserts new watches
    # with arrays using the arbitary name given and the existing key
    # on the other model's watch.  they are not meant to be accessed
    # by [] syntax.  the model is assigned to an ivar of the name 
    # given, which an accessor can be created by the user to access.
    #
    # Book
    #   attr_reader :author
    #   model.watch(:root, ref) do |data|
    #     model.combine(:author, Author.get(data[:author_id]))
    #   end
    # ...
    # book = Book.get(1)
    # book.attr("name") #=> "My Book"
    # book.author.attr("name") #=> "Joe Noon"
    def combine(name, model)
      model.api.watches.each_pair do |k, data|
        @api.watch_data([name, k], data)
      end
      rmext_ivar(name, model)
    end

    def always(&block)
      block.weak!
      rmext_on(:ready, &block)
      if ready?
        rmext_block_on_main_q(block, self)
      end
      # return an unbinder
      weak_self = WeakRef.new(self)
      lambda do
        if weak_self.weakref_alive?
          rmext_off(:ready, &block)
        end
      end
    end

    def once(&block)
      @waiting_once = self
      if ready?
        rmext_block_on_main_q(block, self)
      else
        rmext_once(:ready, &block)
      end
      self
    end

    def cancel_block(&block)
      rmext_off(:ready, &block)
    end

    def attr(keypath)
      root.attr(keypath)
    end

    def hasValue?
      root.hasValue?
    end

    def self.create(&block)
      x = new
      block.call(x)
      x
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
      @models = models.flatten.compact
      @complete_blocks = {}
      if @models.any?
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
          model.once(&block)
        end
      else
        ready!
      end
    end

    def ready!
      @ready = true
      rmext_trigger2(:ready, models)
      @waiting_once = nil
    end

    def cancel!
      models_outstanding = @complete_blocks.keys.dup
      while model = models_outstanding.pop
        if blk = @complete_blocks[model]
          @complete_blocks.delete(model)
          model.cancel_block(&blk)
        end
      end
      @waiting_once = nil
    end

    def ready?
      !!@ready
    end

    def once(&block)
      @waiting_once = self
      if ready?
        rmext_block_on_main_q(block, models)
      else
        rmext_once(:ready, &block)
      end
      self
    end

    def cancel_block(&block)
      rmext_off(:ready, &block)
    end

  end

  class OrderedSnaps

    attr_accessor :transformations_table, :ref

    def initialize
      @snaps = []
      @transformations_table = {}
    end

    def transform(&block)
      @transform_block = block.weak!
    end

    def results
      if @transform_block
        @snaps.map do |snap|
          @transformations_table[snap] ||= @transform_block.call(snap)
        end
      else
        @snaps
      end
    end

    def add(snap, prev)
      p "added", snap.name, "after", prev
      if current_index = @snaps.index { |existing| existing.name == snap.name }
        @snaps.delete_at(current_index)
      end
      if prev && (index = @snaps.index { |existing| existing.name == prev })
        @snaps.insert(index, snap)
      else
        @snaps.push(snap)
      end
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
          raise "#{className} introduced a model that is not ready: #{@data.inspect}"
        end
        @data_unbinder = @data.always do
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
          raise "#{className} introduced a model that is not ready: #{@model.inspect}"
        end
        @model_unbinder = @model.always do
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
          raise "#{className} introduced a model that is not ready: #{@model.inspect}"
        end
        @model_unbinder = @model.always do
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
