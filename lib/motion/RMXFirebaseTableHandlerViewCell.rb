class RMXFirebaseTableHandlerViewCell < RMXTableHandlerViewCell

  extend RMXFirebaseHandleModel

  def prepareForReuse
    if @model
      @model_unbinder.call if @model_unbinder
      @model_unbinder = nil
    end
    @model = nil
    reset
  end

  def changed
  end

  def pending
  end

  def model
    @model
  end

  def model=(val)
    return @model if val == @model
    @model = val
    if @model
      @model_unbinder = @model.always do |m|
        next unless m == @model
        m.ready? ? changed : pending
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
