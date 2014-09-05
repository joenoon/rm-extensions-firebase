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

  def pending
    reset
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
        @sizerModels[@model] ||= begin
          p "sizer watch", @model
          @model.changed do |m|
            p "changed", m
            if th = tableHandler
              th.invalidateHeightForData(m, reuseIdentifier:sizerCellReuseIdentifier)
            end
          end
        end
        @model = nil
      else
        @model_unbinder = @model.always do
          @model.loaded? ? changed : pending
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
