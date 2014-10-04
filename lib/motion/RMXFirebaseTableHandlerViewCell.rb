class RMXFirebaseTableHandlerViewCell < RMXTableHandlerViewCell

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
      if sizerCellReuseIdentifier
        reset
        changed
        @sizerModels ||= {}
        @sizerModels[@model] ||= begin
          @model.weakChangedMainSignal
          .takeUntil(rac_willDeallocSignal)
          .subscribeNext(->(m) {
            if th = tableHandler
              th.invalidateHeightForData(m, reuseIdentifier:sizerCellReuseIdentifier)
            end
          }.rmx_weak!)
        end
        @model = nil
      else
        unbind_model
        @model_unbinder = @model.weakAlwaysMainSignal
        .takeUntil(rac_willDeallocSignal)
        .subscribeNext(->(m) {
          m.ready? ? changed : pending
        }.rmx_weak!)
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
