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
    
    include ::RMExtensions::CommonMethods

    attr_accessor :map
    
    def initialize
      @map = ::RMExtensions::WeakToStrongHash.new
      @own = ::RMExtensions::WeakToStrongHash.new
    end

    def own_snapshot(snap)
      @own[snap.ref] = snap
      return
    end

    def track(fquery, handler, leaf)
      @map[leaf] ||= {}
      @map[leaf][handler] = fquery
      return
    end

    def off(handle=nil, cleanup_only=false)
      object_context = !handle.is_a?(Integer) && handle
      handle = nil if object_context
      keys = [] + @map.keys
      while other = keys.pop
        # p "other", other.rmext_object_desc
        next if object_context && other != object_context
        if hash = @map[other]
          hash_keys = [] + hash.keys
          while handler = hash_keys.pop
            if !handle || handler == handle
              fquery = hash[handler]
              @own.delete(fquery)
              hash.delete(handler)
              unless cleanup_only
                # p fquery.description, "removeObserverWithHandle", handler #, caller
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
    def rmext_dealloc
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

  DEBUG_IDENTITY_MAP = RMExtensions::Env['rmext_firebase_debug_identity_map'] == '1'
  DEBUG_MODEL_DEALLOC = RMExtensions::Env['rmext_firebase_debug_model_dealloc'] == '1'

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
      value && value[key]
    end

    def valueForUndefinedKey(key)
      nil
    end

    def value
      snap.value
    end

    def ref
      snap.ref
    end

    def name
      snap.name
    end

    def priority
      snap.priority
    end

    def count
      snap.childrenCount
    end

    def children
      snap.children.each.map { |x| DataSnapshot.new(x) }
    end

  end

  class Listener

    include RMExtensions::CommonMethods

    attr_accessor :snapshot, :ref, :callback, :handle, :value_required
    rmext_weak_attr_accessor :callback_owner

    def rmext_dealloc
      stop!
      super
    end

    def ready?
      !!@ready
    end

    def cancelled?
      !!@cancelled
    end

    def start!
      weak_self = WeakRef.new(self)
      cancel_block = lambda do |err|
        if weak_self.weakref_alive?
          @cancelled = err
          rmext_trigger(:cancelled, self)
          rmext_trigger(:finished, self)
        end
      end
      @handle = ref.on(:value, { :disconnect => cancel_block }) do |snap|
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

    def stop!
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

    attr_accessor :watches

    def clear!
      @cancelled = false
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

    def cancelled?
      !!@cancelled
    end

    def ready!
      @ready = true
      rmext_trigger(:ready, self)
      rmext_trigger(:finished, self)
    end

    def cancelled!
      @cancelled = true
      rmext_trigger(:cancelled, self)
      rmext_trigger(:finished, self)
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
        current.rmext_off(:finished, self)
      end
      data.rmext_on(:finished) do
        if @watches.values.all?(&:ready?)
          ready!
        elsif @watches.values.any?(&:cancelled?)
          cancelled!
        end
      end
      @watches[name] = data
    end

    def watch(name, ref, opts={}, &block)
      data = Listener.new
      data.ref = ref
      if opts[:required]
        data.value_required = true
      end
      unless block.nil?
        data.callback = block.weak!
        data.callback_owner = block.owner
      end
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

    attr_accessor :opts

    attr_reader :api, :root

    def initialize(opts=nil)
      @opts = opts
      @dependencies = {}
      @waiting_once = []
      internal_setup
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
      @ready = true
      rmext_trigger(:ready, self)
      rmext_trigger(:finished, self)
      @waiting_once.pop
    end

    def cancelled!
      @cancelled = true
      rmext_trigger(:cancelled, self)
      rmext_trigger(:finished, self)
      @waiting_once.pop
    end

    # override
    def setup
    end

    def internal_setup
      @api = Coordinator.new
      @api.rmext_on(:finished) do
        check_ready
      end
      setup
    end

    def check_ready
      if @api.cancelled? || @dependencies.values.any?(&:cancelled?)
        cancelled!
      elsif @api.ready? && @dependencies.values.all?(&:ready?)
        ready!
      end
    end

    def watch(name, ref, opts={}, &block)
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
      @dependencies[name] = model
      rmext_ivar(name, model)
      model.rmext_on(:finished) do
        check_ready
      end
    end

    def always(&block)
      return false if cancelled?
      if ready?
        rmext_block_on_main_q(block, self)
      end
      # return an unbinder
      block.weak!
      rmext_on(:ready, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:ready, &block)
        end
      end
      rmext_once(:cancelled, &unbinder)
      unbinder
    end

    def once(&block)
      if ready? || cancelled?
        rmext_block_on_main_q(block, self)
      else
        @waiting_once << [ self, block.owner ]
        rmext_once(:finished, &block)
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
        return existing.retain.autorelease
      else
        if DEBUG_IDENTITY_MAP
          p "MISS!", className, opts
        end
        res = new(opts)
        if opts
          identity_map[[ className, opts ]] ||= res
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

    attr_accessor :models

    def initialize(*models)
      @waiting_once = []
      @ready = false
      @models = models.flatten.compact
      @complete_blocks = {}
      if @models.any?
        _models = @models.dup
        _pairs = []
        while model = _models.shift
          blk = proc do
            # p "COMPLETE!"
            @complete_blocks.delete(model)
            if @complete_blocks.empty?
              ready!
            end
          end
          @complete_blocks[model] = blk
          _pairs << [ model, blk ]
        end
        while pair = _pairs.shift
          pair[0].once(&pair[1])
        end
      else
        ready!
      end
    end

    def ready_models
      outs = []
      _models = [] + @models
      while model = _models.shift
        if model.ready?
          outs << model
        end
      end
      outs
    end

    def cancelled_models
      outs = []
      _models = [] + @models
      while model = _models.shift
        if model.cancelled?
          outs << model
        end
      end
      outs
    end

    def ready!
      @ready = true
      rmext_trigger(:ready, ready_models)
      @waiting_once.pop
    end

    def cancel!
      models_outstanding = @complete_blocks.keys.dup
      while model = models_outstanding.pop
        if blk = @complete_blocks[model]
          @complete_blocks.delete(model)
          model.cancel_block(&blk)
        end
      end
      @waiting_once.pop
    end

    def ready?
      !!@ready
    end

    def once(&block)
      if ready?
        rmext_block_on_main_q(block, ready_models)
      else
        @waiting_once << [ self, block.owner ]
        rmext_once(:ready, &block)
      end
      self
    end

    def cancel_block(&block)
      rmext_off(:ready, &block)
    end

  end

  class Collection

    include RMExtensions::CommonMethods

    attr_accessor :transformations_table, :ref, :snaps, :cancelled

    # public
    def ready?
      !!@ready
    end

    # public
    def cancelled?
      !!@cancelled
    end

    # returns transformations, if they are Models, they are not guaranteed ready
    def results
      @snaps.map do |snap|
        store_transform(snap)
      end.compact
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

    # public, completes with ready transformations
    def transformed(&block)
      results = self.results
      if (snap = results.first) && snap.is_a?(Model)
        FirebaseExt::Batch.new(results).once(&block)
      else
        rmext_block_on_main_q(block, results)
      end
      self
    end

    # completes with `self` once, when the collection is ready.
    # retains `self` and the sender until complete
    def once(&block)
      if ready?
        rmext_block_on_main_q(block, self)
      else
        @waiting_once << [ self, block.owner ]
        rmext_once(:ready, &block)
      end
      self
    end

    # completes with `self` immediately if ready, and every time the collection :ready fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def always(&block)
      return false if cancelled?
      if ready?
        rmext_block_on_main_q(block, self)
      end
      # return an unbinder
      block.weak!
      rmext_on(:ready, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:ready, &block)
        end
      end
      rmext_once(:cancelled, &unbinder)
      unbinder
    end

    # completes with `self` every time the collection :changed fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def changed(&block)
      return false if cancelled?
      # return an unbinder
      block.weak!
      rmext_on(:changed, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:changed, &block)
        end
      end
      rmext_once(:cancelled, &unbinder)
      unbinder
    end

    # completes with `self`, `snap`, `prev` every time the collection :added fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def added(&block)
      return false if cancelled?
      # return an unbinder
      block.weak!
      rmext_on(:added, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:added, &block)
        end
      end
      rmext_once(:cancelled, &unbinder)
      unbinder
    end

    # completes with `self`, `snap` every time the collection :removed fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def removed(&block)
      return false if cancelled?
      # return an unbinder
      block.weak!
      rmext_on(:removed, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:removed, &block)
        end
      end
      rmext_once(:cancelled, &unbinder)
      unbinder
    end

    # completes with `self`, `snap`, `prev` every time the collection :moved fires.
    # does not retain `self` or the sender.
    # returns an "unbinder" that can be called to stop listening.
    def moved(&block)
      return false if cancelled?
      # return an unbinder
      block.weak!
      rmext_on(:moved, &block)
      weak_block_owner = WeakRef.new(block.owner)
      weak_self = WeakRef.new(self)
      unbinder = proc do
        if weak_self.weakref_alive? && weak_block_owner.weakref_alive?
          rmext_off(:moved, &block)
        end
      end
      rmext_once(:cancelled, &unbinder)
      unbinder
    end

    # internal
    def initialize(ref)
      @waiting_once = []
      @snaps = []
      @transformations_table = {}
      setup_ref(ref)
    end

    # internal
    def setup_ref(ref, mode=:truncate)
      @ready = false
      @cancelled = false
      weak_self = WeakRef.new(self)
      cancel_block = lambda do |err|
        if weak_self.weakref_alive?
          @cancelled = err
          cancelled!
        end
      end
      ref.once(:value, { :disconnect => cancel_block }) do |collection|
        @collection = collection
        children = collection.children
        case mode
        when :append
          @snaps += children
        when :prepend
          @snaps = children + @snaps
        when :truncate
          @snaps = [] + children
        end
        children.each do |child|
          prev = @snaps[@snaps.index(child) - 1]
          rmext_trigger(:added, self, child, (prev ? prev.name : nil))
        end
        ref.on(:added) do |snap, prev|
          add(snap, prev)
        end
        ref.on(:removed) do |snap|
          remove(snap)
        end
        ref.on(:moved) do |snap, prev|
          add(snap, prev)
        end
        ready!
      end
      @ref = ref
    end

    # internal
    def ready!
      @ready = true
      rmext_trigger(:ready, self)
      rmext_trigger(:changed, self)
      @waiting_once.pop
    end

    # internal
    def cancelled!
      @cancelled = true
      rmext_trigger(:cancelled, self)
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
      @transformations_table[snap] ||= transform(snap)
    end

    # internal
    def add(snap, prev)
      moved = false
      if current_index = @snaps.index { |existing| existing.name == snap.name }
        if current_index == 0 && prev.nil?
          return
        elsif current_index > 0 && prev && (current_prev = @snaps[current_index - 1]) && current_prev.name == prev
          return
        end
        moved = true
        @snaps.delete_at(current_index)
      end
      if prev && (index = @snaps.index { |existing| existing.name == prev })
        @snaps.insert(index + 1, snap)
      else
        @snaps.unshift(snap)
      end
      if moved
        rmext_trigger(:moved, self, snap, prev)
      else
        rmext_trigger(:added, self, snap, prev)
      end
      rmext_trigger(:changed, self)
      rmext_trigger(:ready, self) if ready?
    end

    # internal
    def remove(snap)
      if current_index = @snaps.index { |existing| existing.name == snap.name }
        @snaps.delete_at(current_index)
        rmext_trigger(:removed, self, snap)
        rmext_trigger(:changed, self)
        rmext_trigger(:ready, self) if ready?
      end
    end

    # this is the method you should call
    def self.get(ref)
      if existing = identity_map[ref.description]
        if DEBUG_IDENTITY_MAP
          p "HIT!", className, ref.description, existing.retainCount
        end
        return existing.retain.autorelease
      else
        if DEBUG_IDENTITY_MAP
          p "MISS!", className, ref.description
        end
        res = new(ref)
        identity_map[ref.description] ||= res
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
          raise "#{className} tried to use a model that is not ready: #{@model.rmext_object_desc}"
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
          raise "#{className} tried to use a model that is not ready: #{@model.inspect}"
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
