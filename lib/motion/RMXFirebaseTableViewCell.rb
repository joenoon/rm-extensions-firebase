class RMXFirebaseTableViewCell < RMXTableViewCell

  extend RMXFirebaseHandleModel

  def prepareForReuse
    if @data
      @data_unbinder.call if @data_unbinder
      @data_unbinder = nil
    end
    @data = nil
    reset
  end

  def reset
  end

  def changed
  end

  def data=(val)
    return @data if val == @data
    @data = val
    if @data
      unless @data.ready?
        raise "#{className} tried to use a model that is not ready: #{@data.inspect}"
      end
      @data_unbinder = @data.always do |m|
        next unless m == @data
        changed
      end
    end
    @data
  end

  def model
    @data
  end

  def model=(val)
    self.data = val
  end

end
