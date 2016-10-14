require_relative "setup.rb"

class DescriptorTest < MiniTest::Test

  def test_list
    # check available descriptors
    assert_equal 355,PhysChem.descriptors.size,"incorrect number of physchem descriptors"
    assert_equal 15,PhysChem.openbabel_descriptors.size,"incorrect number of Openbabel descriptors"
    assert_equal 295,PhysChem.cdk_descriptors.size,"incorrect number of Cdk descriptors"
    assert_equal 45,PhysChem.joelib_descriptors.size,"incorrect number of Joelib descriptors"
  end

  def test_smarts
    c = OpenTox::Compound.from_smiles "N=C=C1CCC(=F=FO)C1"
    File.open("tmp.png","w+"){|f| f.puts c.png}
    s = Smarts.find_or_create_by(:smarts => "F=F")
    result = c.smarts_match [s]
    assert_equal [1], result
    smarts = ["CC", "C", "C=C", "CO", "F=F", "C1CCCC1", "NN"].collect{|s| Smarts.find_or_create_by(:smarts => s)}
    result = c.smarts_match smarts
    assert_equal [1, 1, 1, 0, 1, 1, 0], result
    smarts_count = [10, 6, 2, 0, 2, 10, 0]
    result = c.smarts_match smarts, true
    assert_equal smarts_count, result
  end

  def test_compound_openbabel_single
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    feature = PhysChem.find_or_create_by(:name => "Openbabel.logP")
    result = c.calculate_properties([feature])
    assert_equal 1.12518, result.first.round(5)
    assert_equal 1.12518, c.properties[feature.id.to_s].round(5)
  end

  def test_compound_cdk_single
    c = OpenTox::Compound.from_smiles "c1ccccc1"
    feature = PhysChem.find_or_create_by(:name => "Cdk.AtomCount.nAtom")
    result = c.calculate_properties([feature])
    assert_equal 12, result.first
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    feature = PhysChem.find_or_create_by(:name => "Cdk.AtomCount.nAtom")
    result = c.calculate_properties([feature])
    assert_equal 17, result.first
    c_types = {"Cdk.CarbonTypes.C1SP1"=>1, "Cdk.CarbonTypes.C2SP1"=>0, "Cdk.CarbonTypes.C1SP2"=>0, "Cdk.CarbonTypes.C2SP2"=>1, "Cdk.CarbonTypes.C3SP2"=>0, "Cdk.CarbonTypes.C1SP3"=>2, "Cdk.CarbonTypes.C2SP3"=>1, "Cdk.CarbonTypes.C3SP3"=>1, "Cdk.CarbonTypes.C4SP3"=>0}
    physchem_features = c_types.collect{|t,nr| PhysChem.find_or_create_by(:name => t)}
    result = c.calculate_properties physchem_features
    assert_equal [1, 0, 0, 1, 0, 2, 1, 1, 0], result
  end

  def test_compound_joelib_single
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    result = c.calculate_properties [PhysChem.find_or_create_by(:name => "Joelib.LogP")]
    assert_equal 2.65908, result.first
  end

  def test_compound_all
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    amr = PhysChem.find_or_create_by(:name => "Cdk.ALOGP.AMR", :library => "Cdk")
    sbonds = PhysChem.find_by(:name => "Openbabel.sbonds")
    result = c.calculate_properties([amr,sbonds])
    assert_equal 30.8723, result[0]
    assert_equal 5, result[1]
  end

  def test_compound_descriptor_parameters
    PhysChem.descriptors
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    result = c.calculate_properties [ "Openbabel.logP", "Cdk.AtomCount.nAtom", "Joelib.LogP" ].collect{|d| PhysChem.find_or_create_by(:name => d)}
    assert_equal 3, result.size
    assert_equal 1.12518, result[0].round(5)
    assert_equal 17.0, result[1].round(5)
    assert_equal 2.65908, result[2].round(5)
  end

end
