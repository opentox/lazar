require_relative "setup.rb"

class CompoundTest < MiniTest::Test

  def test_0_compound_from_smiles
    c = OpenTox::Compound.from_smiles "F[B-](F)(F)F.[Na+]"
    assert_equal "InChI=1S/BF4.Na/c2-1(3,4)5;/q-1;+1", c.inchi.chomp
    assert_equal "F[B-](F)(F)F.[Na+]", c.smiles, "A failure here might be caused by a compound webservice running on 64bit architectures using an outdated version of OpenBabel. Please install OpenBabel version 2.3.2 or higher." # seems to be fixed in 2.3.2
  end

  def test_1_compound_from_smiles
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    assert_equal "InChI=1S/C6H9NO/c1-5(4-7)3-6(2)8/h5H,3H2,1-2H3", c.inchi
    assert_equal "CC(C#N)CC(=O)C", c.smiles
  end

  def test_2_compound_from_smiles
    c = OpenTox::Compound.from_smiles "N#[N+]C1=CC=CC=C1.F[B-](F)(F)F"
    assert_equal "InChI=1S/C6H5N2.BF4/c7-8-6-4-2-1-3-5-6;2-1(3,4)5/h1-5H;/q+1;-1", c.inchi
    assert_equal "F[B-](F)(F)F.N#[N+]c1ccccc1", c.smiles
  end

  def test_compound_from_name
    c = OpenTox::Compound.from_name "Benzene"
    assert_equal "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H", c.inchi
    assert_equal "c1ccccc1", c.smiles
  end

  def test_compound_from_inchi
    c = OpenTox::Compound.from_inchi "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"
    assert_equal "c1ccccc1", c.smiles
  end

  def test_sdf_import
    c = OpenTox::Compound.from_sdf File.read(File.join DATA_DIR, "acetaldehyde.sdf")
    assert_equal "InChI=1S/C2H4O/c1-2-3/h2H,1H3", c.inchi
    assert_equal "CC=O", c.smiles
    assert c.names.include? "Acetylaldehyde"
  end

  def test_sdf_export
    c = OpenTox::Compound.from_smiles "CC=O"
    assert_match /7  6  0  0  0  0  0  0  0  0999 V2000/, c.sdf
  end

  def test_compound_image
    c = OpenTox::Compound.from_inchi "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"
    testbild = "/tmp/testbild.png"
    File.open(testbild, "w"){|f| f.puts c.png}
    assert_match "image/png", `file -b --mime-type /tmp/testbild.png`
    File.unlink(testbild)
  end

  # OpenBabel segfaults randomly during inchikey calculation
  def test_inchikey
    c = OpenTox::Compound.from_inchi "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"
    p c
    assert_equal "UHOVQNZJYSORNB-UHFFFAOYSA-N", c.inchikey
  end

  def test_cid
    c = OpenTox::Compound.from_inchi "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"
    assert_equal "241", c.cid
  end

  def test_chemblid
    c = OpenTox::Compound.from_inchi "InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"
    #assert_equal "CHEMBL277500", c.chemblid
    assert_equal "CHEMBL581676", c.chemblid
  end

  def test_sdf_storage
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"
    c.sdf
    assert !c.sdf_id.nil?
  end

  def test_fingerprint
    c = OpenTox::Compound.from_smiles "CC(=O)CC(C)C#N"

    assert c.fp4.collect{|fid| Feature.find(fid).name}.include? ("1,3-Tautomerizable")
    assert_equal c.fp4.size, c.fp4_size
  end

  def test_neighbors
    d = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.csv")
    d.compounds.each do |c|
      refute_nil c.fp4
    end
    c = d.compounds[371]
    assert c.neighbors.size >= 19
  end

  def test_openbabel_segfault
    inchi = "InChI=1S/C19H27NO7/c1-11-9-19(12(2)27-19)17(23)26-14-6-8-20(4)7-5-13(15(14)21)10-25-16(22)18(11,3)24/h5,11-12,14,24H,6-10H2,1-4H3/b13-5-/t11-,12-,14-,18-,19?/m1/s1"

    #r = `echo "#{inchi}" | babel -iinchi - -oinchi`
    c = Compound.from_inchi(inchi)
    assert_nil c
  end
end
