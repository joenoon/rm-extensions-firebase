class RMXFirebaseTableHandlerViewCell < RMXTableHandlerViewCell

  extend RMXFirebaseHandleModel

  def prepareForReuse
    if @model
      @model_unbinder.dispose if @model_unbinder
      @model_unbinder = nil
    end
    @model = nil
    reset
  end

  def changed
  end

  def model
    @model
  end

  def model=(val)
    return @model if val == @model
    @model = val
    if @model
      if sizerCellReuseIdentifier
        reset
        changed
        @sizerModels ||= {}
        unless @sizerModels.key?(@model.cache_key)
          @sizerModels[@model.cache_key] = true
          @model.ref.changed do |m|
            if th = tableHandler
              th.invalidateHeightForCacheKey(m.cache_key, reuseIdentifier:sizerCellReuseIdentifier)
            end
          end
        end
        @model = nil
      else
        @model_unbinder = @model.ref.always do |m|
          @model = m
          changed
        end
      end
    end
    @model
  end

  def data
    model
  end

  def data=(data)
    self.model = data
  end

end
