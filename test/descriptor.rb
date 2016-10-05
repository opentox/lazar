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
    PhysChem.openbabel_descriptors # required for descriptor initialisation, TODO: move into libs
    PhysChem.find_or_create_by(:name => "Openbabel.logP")
    result = c.calculated_physchem [PhysChem.find_or_create_by(:name => "Openbabel.logP")]
    assert_equal 1.12518, result.first.last.round(5)
  end

  def test_compound_cdk_single
    PhysChem.cdk_descriptors # required for descriptor initialisation, TODO: move into libs
    c = OpenTox::Compound.from_smiles "c1ccccc1"
    result = c.calculated_physchem [PhysChem.find_or_create_by(:name => "Cdk.AtomCount.nAtom")]
    assert_equal 12, result.first.last
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    result = c.calculated_physchem [PhysChem.find_or_create_by(:name => "Cdk.AtomCount.nAtom")]
    assert_equal 17, result.first.last
    c_types = {"Cdk.CarbonTypes.C1SP1"=>1, "Cdk.CarbonTypes.C2SP1"=>0, "Cdk.CarbonTypes.C1SP2"=>0, "Cdk.CarbonTypes.C2SP2"=>1, "Cdk.CarbonTypes.C3SP2"=>0, "Cdk.CarbonTypes.C1SP3"=>2, "Cdk.CarbonTypes.C2SP3"=>1, "Cdk.CarbonTypes.C3SP3"=>1, "Cdk.CarbonTypes.C4SP3"=>0}
    physchem_features = c_types.collect{|t,nr| PhysChem.find_or_create_by(:name => t)}
    result = c.calculated_physchem physchem_features
    assert_equal [1, 0, 0, 1, 0, 2, 1, 1, 0], result.values
  end

  def test_compound_joelib_single
    PhysChem.joelib_descriptors # required for descriptor initialisation, TODO: move into libs
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    result = c.calculated_physchem [PhysChem.find_or_create_by(:name => "Joelib.LogP")]
    assert_equal 2.65908, result.first.last
  end

  def test_compound_all
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    result = c.calculated_physchem PhysChem.descriptors
    amr = PhysChem.find_or_create_by(:name => "Cdk.ALOGP.AMR", :library => "Cdk")
    sbonds = PhysChem.find_by(:name => "Openbabel.sbonds")
    assert_equal 30.8723, result[amr.id.to_s]
    assert_equal 5, result[sbonds.id.to_s]
  end

  def test_compound_descriptor_parameters
    PhysChem.descriptors
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    result = c.calculated_physchem [ "Openbabel.logP", "Cdk.AtomCount.nAtom", "Joelib.LogP" ].collect{|d| PhysChem.find_or_create_by(:name => d)}
    assert_equal 3, result.size
    result.each do |fid,v|
      feature = Feature.find(fid)
      case feature.name
      when "Openbabel.logP"
        assert_equal 1.12518, v.round(5)
      when "Cdk.AtomCount.nAtom"
        assert_equal 17.0, v.round(5)
      when "Joelib.LogP"
        assert_equal 2.65908, v.round(5)
      end
    end
  end

end
