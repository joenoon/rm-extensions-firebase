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
      @model_unbinder.call if @model_unbinder
      @model_unbinder = nil
    end
    @model = val
    reset
    if @model
      unless @model.ready?
        raise "#{className} tried to use a model that is not ready: #{@model.rmx_object_desc}"
      end
      @model_unbinder = @model.always do |m|
        unless m == @model
          p "model.always", "m", m, "@model", @model
        end
        next unless m == @model
        changed
      end
    end
    @model
  end

end
