class RMXFirebaseView < RMXView

  extend RMXFirebaseHandleModel

  def reset
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
    return @model if @model == val
    if @model
      @model_unbinder.dispose if @model_unbinder
      @model_unbinder = nil
    end
    @model = val
    reset
    if @model
      @model_unbinder = @model.weakAlwaysMainSignal
      .takeUntil(rac_willDeallocSignal)
      .subscribeNext(->(m) {
        m.hasValue? ? changed : pending
      }.weak!)
    end
    @model
  end

end
