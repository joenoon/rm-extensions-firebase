module FirebaseExt

  class DataSnapshot

    include RMExtensions::CommonMethods

    attr_accessor :snap

    def initialize(snap)
      @snap = snap
    end

    def hasValue?
      !value.nil?
    end

    def attr(keypath)
      valueForKeyPath(keypath)
    end

    def valueForKey(key)
      if v = value
        v[key]
      end
    end

    def valueForUndefinedKey(key)
      nil
    end

    def value
      snap.value
    end

    def ref
      snap.ref
    end

    def name
      snap.name
    end

    def priority
      snap.priority
    end

    def count
      snap.childrenCount
    end

    def children
      snap.children.each.map { |x| DataSnapshot.new(x) }
    end

  end

end
