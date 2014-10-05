class RMXFirebaseTableViewCell < RMXTableViewCell

  extend RMXFirebaseHandleModel

  def prepareForReuse
    unbind_model
    @model = nil
    reset
  end

  def changed
  end

  def pending
    reset
  end

  def unbind_model
    @model_unbinder.dispose if @model_unbinder
    @model_unbinder = nil
  end

  def model
    @model
  end

  def model=(val)
    return @model if val == @model
    @model = val
    if @model
      unbind_model
      @model_unbinder = @model.weakAlwaysMainSignal
      .takeUntil(rac_willDeallocSignal)
      .subscribeNext(->(m) {
        m.ready? ? changed : pending
      }.rmx_unsafe!)
    end
    @model
  end

end
