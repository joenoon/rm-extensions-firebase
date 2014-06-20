module FirebaseExt

  module HandleModel
    def handle(key)
      define_method(key) do
        self.model
      end
      define_method("#{key}=") do |val|
        self.model = val
      end
    end
  end

end
