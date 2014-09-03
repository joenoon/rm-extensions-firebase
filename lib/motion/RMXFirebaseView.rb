class RMXFirebaseView < RMXView

  extend RMXFirebaseHandleModel

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
      @model_unbinder.dispose if @model_unbinder
      @model_unbinder = nil
    end
    @model = val
    reset
    if @model
      @model_unbinder = @model.ref.always do |m|
        @model = m
        changed
      end
    end
    @model
  end

end
