class RMXFirebaseCollection < RMXFirebaseModel

  # public, override required
  def self.transform(snap)
    raise "#{className}.transform(snap): override to return a RMXFirebaseModel based on the snap"
  end

  def self.setup(ref)
    signalsToValues({
      :root => ref.rac_valueSignal
    })
  end

  def self.get(opts=nil)
    return RMXFirebaseCollectionQuery.new(self, opts)
  end

end
