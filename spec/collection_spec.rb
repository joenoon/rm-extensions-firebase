class Bacon::Context
  def after_modifications(collection, &block)
    wait(0.5) do
      collection.once do |snaps|
        snap_names = snaps.map(&:name)
        puts "snap_names: #{snap_names.inspect}\n\n"
        RMX.block_on_main_q(block, snap_names)
      end
    end
  end
end

describe "RMXFirebaseCollection" do

  before do
    Firebase.goOffline
    $firebase = Firebase.alloc.initWithUrl("https://rmext.firebaseio.local/")
    @ref = $firebase["collection_test"]
    @letters = {
      "a" => 10,
      "b" => 20,
      "c" => 30,
      "d" => 40,
      "e" => 50,
      "f" => 60,
      "g" => 70,
      "h" => 80,
      "i" => 90,
      "j" => 100,
      "k" => 110,
      "l" => 120,
      "m" => 130,
      "n" => 140,
      "o" => 150,
      "p" => 160,
      "q" => 170,
      "r" => 180,
      "s" => 190,
      "t" => 200,
      "u" => 210,
      "v" => 220,
      "w" => 230,
      "x" => 240,
      "y" => 250,
      "z" => 260
    }
  end

  describe "a collection" do

    before do
      @col = RMXFirebaseCollection.new(@ref)
      @ref.setValue({})
      @letters.each_pair do |k, pri|
        p "SET", k, pri
        @ref[k].setValue(pri, andPriority:pri)
      end
    end

    it "can move c after v" do
      @ref["c"].setPriority(@letters["v"] + 1)
      after_modifications(@col) do |snap_names|
        snap_names.index("c").should == snap_names.index("v") + 1
      end
    end

    it "can move c after z" do
      @ref["c"].setPriority(@letters["z"] + 1)
      after_modifications(@col) do |snap_names|
        snap_names.index("c").should == snap_names.index("z") + 1
      end
    end

    it "can move c after everything" do
      @ref["c"].setPriority(10000)
      after_modifications(@col) do |snap_names|
        snap_names.last.should == "c"
      end
    end

    it "can move v before f" do
      @ref["v"].setPriority(@letters["f"] - 1)
      after_modifications(@col) do |snap_names|
        snap_names.index("v").should == snap_names.index("f") - 1
      end
    end

    it "can move c before everything" do
      @ref["c"].setPriority(-10000)
      after_modifications(@col) do |snap_names|
        snap_names.first.should == "c"
      end
    end

    it "add a new value before everything" do
      @ref["new"].setValue(".", andPriority:-10000)
      after_modifications(@col) do |snap_names|
        snap_names.first.should == "new"
      end
    end

    it "add a new value after everything" do
      @ref["new"].setValue(".", andPriority:10000)
      after_modifications(@col) do |snap_names|
        snap_names.last.should == "new"
      end
    end

    it "add a new value after j" do
      @ref["new"].setValue(".", andPriority:(@letters["j"] + 1))
      after_modifications(@col) do |snap_names|
        snap_names.index("new").should == snap_names.index("j") + 1
      end
    end

    it "add a new value before j" do
      @ref["new"].setValue(".", andPriority:(@letters["j"] - 1))
      after_modifications(@col) do |snap_names|
        snap_names.index("new").should == snap_names.index("j") - 1
      end
    end

    it "remove a" do
      @ref["a"].removeValue
      after_modifications(@col) do |snap_names|
        snap_names.first.should == "b"
      end
    end

    it "remove z" do
      @ref["z"].removeValue
      after_modifications(@col) do |snap_names|
        snap_names.last.should == "y"
      end
    end

    it "remove j" do
      @ref["j"].removeValue
      after_modifications(@col) do |snap_names|
        snap_names[snap_names.index("i") + 1].should == "k"
      end
    end

  end

end
