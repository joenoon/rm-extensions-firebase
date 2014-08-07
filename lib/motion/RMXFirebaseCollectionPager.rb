# RMXFirebaseCollectionPager
#
# USAGE:
#
# collection_pager = RMXFirebaseCollectionPager.new({
#   :collectionKlass => MyCollectionSubclass,
#   :limit => 10,
#   :base => a_firebase_ref
# })
#
# collection_pager.added do |pager, snap|
#   # do something with latest snap
#   pager.transform(snap).once do |model|
#     # do something with transformed snap
#   end
# end
#
# collection_pager.always_async do |pager|
#   # in async queue here
#   pager.transformed do |models|
#     # in main queue here
#     # do something with models
#     tableView.reloadData
#   end
# end
#
# # at some point in the future, load more:
# collection_pager.loadMore do |hasMore|
#   if hasMore
#     # do something
#   end
# end
#

class RMXFirebaseCollectionPager

  include RMXCommonMethods

  attr_reader :snaps, :transformations_table, :transformations

  def loadMore(&block)
    RMXFirebase::QUEUE.barrier_async do
      sort_collections!
      hasMore = false
      if finished?
        # noop
      elsif @starting_at
        if last_snap = @snaps.last
          if @collections.last.snaps.size > 0
            last_pri = last_snap.priority
            last_name = last_snap.name
            ref = @base.starting_at(last_pri, last_name).limited(@limit + 1)
            hasMore = setup_collection(@collectionKlass.get(ref))
          end
        end
      else
        if first_snap = @snaps.first
          if @collections.first.snaps.size > 0
            first_pri = first_snap.priority
            first_name = first_snap.name
            ref = @base.ending_at(first_pri, first_name).limited(@limit + 1)
            hasMore = setup_collection(@collectionKlass.get(ref))
          end
        end
      end
      RMX.block_on_main_q(block, hasMore)
    end
  end

  # public
  def finished?
    !!@finished
  end

  # public
  def ready?
    @collections.any? && @collections.all? { |x| x.ready? }
  end

  # public
  def cancelled?
    @collections.any? && @collections.any? { |x| x.cancelled? }
  end

  def transform(snap)
    @transformations_table[snap]
  end

  def transformed_async(&block)
    transformed(:async, &block)
  end

  # public, completes with ready transformations
  def transformed(queue=nil, &block)
    RMXFirebase::QUEUE.barrier_async do
      items = @transformations.dup
      if (snap = items.first) && snap.is_a?(RMXFirebaseModel)
        RMXFirebaseBatch.new(items).once(queue, &block)
      else
        RMXFirebase.block_on_queue(queue, items, &block)
      end
    end
    self
  end

  def once_async(&block)
    once(:async, &block)
  end

  # completes with `self` once, when the collection is ready.
  # retains `self` and the sender until complete
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

  # completes with `self` immediately if finished, and when :finished fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def finished(queue=nil, &block)
    return false if cancelled?
    if finished?
      RMXFirebase.block_on_queue(queue, self, &block)
    end
    RMX(self).on(:finished, :queue => queue, &block)
  end

  def always_async(&block)
    always(:async, &block)
  end

  # completes with `self` immediately if ready, and every time :ready fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def always(queue=nil, &block)
    return false if cancelled?
    if ready?
      RMXFirebase.block_on_queue(queue, self, &block)
    end
    RMX(self).on(:ready, :queue => queue, &block)
  end

  # completes with `self` every time :changed fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def changed(queue=nil, &block)
    return false if cancelled?
    RMX(self).on(:changed, :queue => queue, &block)
  end

  # completes with `self`, `snap` every a new snap is added to the end of the set
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def added(queue=nil, &block)
    return false if cancelled?
    RMX(self).on(:added, :queue => queue, &block)
  end

  # completes with `self`, `snap` every time :removed fires.
  # does not retain `self` or the sender.
  # returns an "unbinder" that can be called to stop listening.
  def removed(queue=nil, &block)
    return false if cancelled?
    RMX(self).on(:removed, :queue => queue, &block)
  end

  def initialize(opts={})
    @collectionKlass = opts[:collectionKlass]
    @limit = opts[:limit]
    @base = opts[:base]
    @starting_at = opts[:starting_at]
    @snaps = []
    @transformations_table = {}
    @transformations = []
    @collections = []
    RMXFirebase::QUEUE.barrier_async do
      ref = @base.limited(@limit)
      if @starting_at
        ref = ref.starting_at(@starting_at)
      end
      setup_collection(@collectionKlass.get(ref))
    end
  end

  # internal
  def setup_collection(collection)
    if @collections.include?(collection)
      @finished = true
      RMX(self).trigger(:finished, self)
      return false
    end
    @collections.unshift(collection)
    collection.always(:async) do |_collection|
      RMXFirebase::QUEUE.barrier_async do
        reprocess
      end
    end
    true
  end

  def sort_collections!
    @collections.sort_by! do |collection|
      first_snap_pri = if first_snap = collection.snaps.first
        first_snap.priority
      else
        0
      end
      last_snap_pri = if last_snap = collection.snaps.last
        last_snap.priority
      else
        0
      end
      [ first_snap_pri, last_snap_pri ]
    end
  end

  def reprocess
    sort_collections!
    @snaps = @collections.map(&:snaps).flatten.uniq
    
    if @snaps == @last_snaps
      return
    end

    last_snaps = @last_snaps || []
    @last_snaps = @snaps
    
    @transformations = @collections.map(&:transformations).flatten.uniq
    @transformations_table = @collections.inject({}) do |table, collection|
      table.update(collection.transformations_table)
      table
    end

    most_recent_snap = @snaps.last

    removed_snaps = last_snaps - @snaps
    removed_snaps.each do |snap|
      RMX(self).trigger(:removed, self, snap)
    end

    if added_snap = (@snaps - last_snaps).detect { |x| x == most_recent_snap }
      RMX(self).trigger(:added, self, added_snap)
    end

    RMX(self).trigger(:changed, self)
    try_ready
  end

  def try_ready
    if ready?
      RMX(self).trigger(:ready, self)
    end
  end

end
