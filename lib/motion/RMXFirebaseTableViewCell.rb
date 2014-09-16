class RMXFirebaseTableViewCell < RMXTableViewCell

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
      @model_unbinder = @model.always do |m|
        m.ready? ? changed : pending
      end
    end
    @model
  end

end
