require_relative "setup.rb"

class FeatureTest < MiniTest::Test

  def test_opentox_feature
    @feature = OpenTox::Feature.create(:name => "tost")
    assert_equal true, OpenTox::Feature.where(name: "tost").exists?, "#{@feature.id} is not accessible."
    assert_equal true, OpenTox::Feature.where(id: @feature.id).exists?, "#{@feature.id} is not accessible."

    list = OpenTox::Feature.all
    listsize1 = list.length
    assert_equal true, list.collect{|f| f.id}.include?(@feature.id)
    # modify feature
    @feature2 = OpenTox::Feature.find(@feature.id)
    assert_equal "tost", @feature2[:name]
    assert_equal "tost", @feature2.name
    assert_kind_of Feature, @feature2

    @feature2[:name] = "feature2"
    @feature2.save
    list = OpenTox::Feature.all 
    listsize2 = list.length
    assert_match "feature2", @feature2.name
    refute_match "tost", @feature2.name
    assert_equal listsize1, listsize2

    id = @feature2.id
    @feature2.delete
    assert_nil OpenTox::Feature.find(id)
  end

  def test_duplicated_features
    metadata = {
      :name => "feature duplication test",
    }
    feature = NumericFeature.find_or_create_by metadata
    dup_feature = NumericFeature.find_or_create_by metadata
    assert_kind_of Feature, feature
    assert !feature.id.nil?, "No Feature ID in #{feature.inspect}"
    assert !feature.id.nil?, "No Feature ID in #{dup_feature.inspect}"
    assert_equal feature.id, dup_feature.id
    feature.delete
    assert_nil OpenTox::Feature.find(feature.id)
    assert_nil OpenTox::Feature.find(dup_feature.id)
  end

  def test_smarts_feature
    feature = Smarts.find_or_create_by(:smarts => "CN")
    assert feature.smarts, "CN"
    assert_kind_of Smarts, feature
    feature.smarts = 'cc'
    assert feature.smarts, "cc"
    original = Feature.where(:smarts => 'CN').first
    assert original.smarts, "CN"
  end

  def test_physchem_description
    assert_equal 346, PhysChem.descriptors.size
    assert_equal 15, PhysChem.openbabel_descriptors.size
    assert_equal 286, PhysChem.cdk_descriptors.size
    assert_equal 45, PhysChem.joelib_descriptors.size
    assert_equal 309, PhysChem.unique_descriptors.size
  end

  def test_physchem
    assert_equal 346, PhysChem.descriptors.size
    c = Compound.from_smiles "CC(=O)CC(C)C"
    logP = PhysChem.find_or_create_by :name => "Openbabel.logP"
    assert_equal 1.6215, c.calculate_properties([logP]).first
    jlogP = PhysChem.find_or_create_by :name => "Joelib.LogP"
    assert_equal 3.5951, c.calculate_properties([jlogP]).first
    alogP = PhysChem.find_or_create_by :name => "Cdk.ALOGP.ALogP"
    assert_equal 0.35380000000000034, c.calculate_properties([alogP]).first
  end

end
