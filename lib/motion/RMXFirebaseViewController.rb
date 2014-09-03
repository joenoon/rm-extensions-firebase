class RMXFirebaseViewController < RMXViewController

  extend RMXFirebaseHandleModel

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
      @model_unbinder.dispose if @model_unbinder
      @model_unbinder = nil
    end
    @model = val
    if @model
      @model_unbinder = @model.ref.always do |m|
        @model = m
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
