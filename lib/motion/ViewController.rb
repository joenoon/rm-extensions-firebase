module FirebaseExt

  class ViewController < ::RMExtensions::ViewController

    extend HandleModel

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
        @model_unbinder.call if @model_unbinder
        @model_unbinder = nil
      end
      @model = val
      if @model
        unless @model.ready?
          raise "#{className} tried to use a model that is not ready: #{@model.inspect}"
        end
        @model_unbinder = @model.always do |m|
          next unless m == @model
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

end
