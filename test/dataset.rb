require_relative "setup.rb"

class DatasetTest < MiniTest::Test

  # basics

  def test_create_empty
    d = Dataset.new
    assert_equal Dataset, d.class
    refute_nil d.id
    assert_kind_of BSON::ObjectId, d.id
  end

  def test_all
    d1 = Dataset.new 
    d1.save
    datasets = Dataset.all 
    assert datasets.first.is_a?(Dataset), "#{datasets.first} is not a Dataset."
  end

  # real datasets
  
  def test_import_pubchem
    d = Dataset.from_pubchem_aid 1191
    assert_equal 86, d.compounds.size
    assert_equal 3, d.features.size
    assert_equal ["Inactive"], d.values(d.compounds[10],d.features[2])
    # TODO endpoint name
    # TODO regression import
  end

  def test_import_csv_tsv_with_id
    ["csv","tsv"].each do |ext|
      d = Dataset.from_csv_file "#{DATA_DIR}/input_53.#{ext}"
      assert_equal 53, d.compounds.size
      assert_equal 2, d.features.size
      f = d.features[1]
      assert_equal "ID", f.name
      assert_equal OriginalId, f.class
      assert_equal ["123-30-8"], d.values(d.compounds.first,f)
    end
  end

  def test_import_sdf
    d = Dataset.from_sdf_file "#{DATA_DIR}/PA.sdf"
    assert_equal 36, d.features.size
    assert_kind_of NumericSubstanceProperty, d.substance_property_features[1]
    assert_equal NominalSubstanceProperty, d.substance_property_features.last.class
    assert_equal 602, d.compounds.size
    assert_match "PUBCHEM_XLOGP3_AA", d.warnings.compact.last
  end

  def test_import_hamster
    d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    assert_equal Dataset, d.class
    assert_equal 3, d.features.size
    assert_equal 85, d.compounds.size
    assert_equal NominalBioActivity, d.bioactivity_features.first.class
    csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.csv")
    csv.shift
    csv.each do |row|
      c = Compound.from_smiles row.shift
      assert_equal row, d.values(c,d.bioactivity_features.first)
    end
  end

  def test_import_kazius
    d = Dataset.from_sdf_file "#{Download::DATA}/parts/cas_4337.sdf"
    assert_equal 4337, d.compounds.size
    assert_equal 3, d.features.size
    assert_empty d.warnings
    c = d.compounds[493]
    assert_equal "CCCCOCCCC", c.smiles
    assert_equal ["nonmutagen"], d.values(c,d.bioactivity_features.first)
  end

  def test_import_multicell
    duplicates = [
      "InChI=1S/C6HCl5O/c7-1-2(8)4(10)6(12)5(11)3(1)9/h12H",
      "InChI=1S/C12H8Cl6O/c13-8-9(14)11(16)5-3-1-2(6-7(3)19-6)4(5)10(8,15)12(11,17)18/h2-7H,1H2",
      "InChI=1S/C2HCl3/c3-1-2(4)5/h1H",
      "InChI=1S/C4H5Cl/c1-3-4(2)5/h3H,1-2H2",
      "InChI=1S/C4H7Cl/c1-4(2)3-5/h1,3H2,2H3",
      "InChI=1S/C8H14O4/c1-5-4-8(11-6(2)9)12-7(3)10-5/h5,7-8H,4H2,1-3H3",
      "InChI=1S/C19H30O5/c1-3-5-7-20-8-9-21-10-11-22-14-17-13-19-18(23-15-24-19)12-16(17)6-4-2/h12-13H,3-11,14-15H2,1-2H3",
    ]
    f = File.join Download::DATA, "Carcinogenicity-Rodents.csv"
    d = OpenTox::Dataset.from_csv_file f 
    csv = CSV.read f
    assert_equal NominalBioActivity, d.bioactivity_features.first.class
    assert_equal 1100, d.compounds.size
    assert_equal csv.first.size-2, d.bioactivity_features.size
    duplicates.each do |inchi|
      refute_empty d.values(Compound.from_inchi(inchi),d.warnings_features.first)
    end
  end

  def test_import_isscan
    f = File.join DATA_DIR, "ISSCAN-multi.csv"
    d = OpenTox::Dataset.from_csv_file f 
    csv = CSV.read f
    assert_equal csv.size-1, d.compounds.size
    assert_equal csv.first.size+1, d.features.size
  end

  def test_import_epafhm
    f = File.join Download::DATA, "Acute_toxicity-Fathead_minnow.csv"
    d = OpenTox::Dataset.from_csv_file f
    assert_equal Dataset, d.class
    csv = CSV.read f
    assert_equal csv.size-2, d.compounds.size
    assert_equal csv.first.size+1, d.features.size
    assert_match "Acute_toxicity-Fathead_minnow.csv",  d.source
    assert_equal "Acute_toxicity-Fathead_minnow",  d.name
    feature = d.bioactivity_features.first
    assert_kind_of NumericFeature, feature
    assert_equal -Math.log10(0.0113), d.values(d.compounds.first,feature).first
    assert_equal -Math.log10(0.00323), d.values(d.compounds[4],feature).first
    d2 = Dataset.find d.id
    assert_equal -Math.log10(0.0113), d2.values(d2.compounds[0],feature).first
    assert_equal -Math.log10(0.00323), d2.values(d2.compounds[4],feature).first
  end

  def test_multiple_uploads
    datasets = []
    2.times do
      d = Dataset.from_csv_file("#{DATA_DIR}/hamster_carcinogenicity.csv")
      datasets << d
    end
    assert_equal datasets[0],datasets[1]
  end

  # batch predictions

  def test_create_without_features_smiles_and_inchi
    ["smiles", "inchi"].each do |type|
      d = Dataset.from_csv_file File.join(DATA_DIR,"batch_prediction_#{type}_small.csv")
      assert_equal Dataset, d.class
      refute_nil d.id
      dataset = Dataset.find d.id
      assert_equal 3, d.compounds.size
    end
  end

  # dataset operations

  def test_folds
    dataset = Dataset.from_csv_file File.join(Download::DATA,"Lowest_observed_adverse_effect_level-Rats.csv")
    dataset.folds(10).each do |fold|
      fold.each do |d|
        assert_operator d.compounds.size, :>=, d.compounds.uniq.size
      end
      refute_empty fold[0].compounds
      refute_empty fold[1].compounds
      refute_empty fold[0].data_entries
      refute_empty fold[1].data_entries
      assert_operator fold[0].compounds.size, :>=, fold[1].compounds.size
      assert_equal dataset.substances.size, fold.first.substances.size + fold.last.substances.size
      assert_empty (fold.first.substances & fold.last.substances)
    end
  end

  def test_copy
    d = Dataset.from_csv_file("#{DATA_DIR}/hamster_carcinogenicity.csv")
    copy = d.copy
    assert_equal d.data_entries, copy.data_entries
    assert_equal d.name, copy.name
    assert_equal d.id.to_s, copy.source
  end

  def test_merge
    kazius = Dataset.from_sdf_file "#{Download::DATA}/parts/cas_4337.sdf"
    hansen = Dataset.from_csv_file "#{Download::DATA}/parts/hansen.csv"
    efsa = Dataset.from_csv_file "#{Download::DATA}/parts/efsa.csv"
    datasets = [hansen,efsa,kazius]
    map = {"mutagen" => "mutagenic", "nonmutagen" => "non-mutagenic"}
    dataset = Dataset.merge datasets: datasets, features: datasets.collect{|d| d.bioactivity_features.first}, value_maps: [nil,nil,map], keep_original_features: true, remove_duplicates: true
    assert_equal 8281, dataset.compounds.size
    assert_equal 9, dataset.features.size
    c = Compound.from_smiles("C/C=C/C=O")
    assert_equal ["mutagenic"], dataset.values(c,dataset.merged_features.first)
  end

  # serialisation

  def test_to_csv
    d = Dataset.from_csv_file "#{DATA_DIR}/multicolumn.csv"
    csv = CSV.parse(d.to_csv)
    assert_equal "3 5", csv[3][0]
    assert_match "3, 5", csv[3][9]
    assert_match "Duplicate", csv[3][9]
    assert_equal '7,c1nccc1,[N]1C=CC=C1,1,,false,,,1.0,', csv[5].join(",")
  end

  def test_to_sdf
    d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.mini.csv"
    File.open("#{DATA_DIR}/tmp.sdf","w+") do |f|
      f.puts d.to_sdf
    end
    d2 = Dataset.from_sdf_file "#{DATA_DIR}/tmp.sdf"
    assert_equal d.compounds.size, d2.compounds.size
    `rm #{DATA_DIR}/tmp.sdf`
  end

  # special cases/details

  def test_dataset_accessors
    d = Dataset.from_csv_file "#{DATA_DIR}/multicolumn.csv"
    refute_nil d.warnings
    assert d.warnings.grep(/Duplicate compound/)  
    assert d.warnings.grep(/3, 5/)  
    assert_equal 9, d.features.size
    assert_equal 5, d.compounds.uniq.size
    assert_equal 5, d.compounds.collect{|c| c.inchi}.uniq.size
    # create empty dataset
    new_dataset = Dataset.find d.id
    # get metadata
    assert_match "multicolumn.csv",  new_dataset.source
    assert_equal "multicolumn",  new_dataset.name
    # get features
    assert_equal 9, new_dataset.features.size
    assert_equal 5, new_dataset.compounds.uniq.size
    c = new_dataset.compounds.last
    f = new_dataset.substance_property_features.first
    assert_equal ["1"], new_dataset.values(c,f)
    f = new_dataset.substance_property_features.last.id
    assert_equal [1.0], new_dataset.values(c,f)
    f = new_dataset.substance_property_features[2]
    assert_equal ["false"], new_dataset.values(c,f)
  end

  def test_create_from_file_with_wrong_smiles_compound_entries
    d = Dataset.from_csv_file File.join(DATA_DIR,"wrong_dataset.csv")
    refute_nil d.warnings
    assert_match /2|3|4|5|6|7|8/, d.warnings.join
  end

  def test_from_csv_classification
    ["int", "float", "string"].each do |mode|
      d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.mini.bool_#{mode}.csv"
      csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.mini.bool_#{mode}.csv")
      csv.shift
      csv.each do |row|
        c = Compound.from_smiles row.shift
        assert_equal row, d.values(c,d.bioactivity_features.first)
      end
    end
  end

  def test_from_csv2
    File.open("#{DATA_DIR}/temp_test.csv", "w+") { |file| file.write("SMILES,Hamster\nCC=O,true\n ,true\nO=C(N),true") }
    dataset = Dataset.from_csv_file "#{DATA_DIR}/temp_test.csv"
    assert_equal "Cannot parse SMILES compound '' at line 3 of /home/ist/lazar/test/data/temp_test.csv, all entries are ignored.",  dataset.warnings.last
    File.delete "#{DATA_DIR}/temp_test.csv"
  end

  def test_same_feature
    datasets = []
    features = []
    2.times do |i|
      d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.mini.csv"
      features << d.features.first
      assert features[0].id==features[-1].id,"re-upload should find old feature, but created new one"
      datasets << d
    end
  end

  def test_simultanous_upload
    skip
    threads = []
    3.times do |t|
      threads << Thread.new(t) do |up|
        d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
        assert_equal OpenTox::Dataset, d.class
        assert_equal 3, d.features.size
        assert_equal 85, d.compounds.size
        csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.csv")
        csv.shift
        csv.each do |row|
          c = Compound.from_smiles(row.shift)
          assert_equal row, d.values(c,d.bioactivity_features.first)
        end
      end
    end
    threads.each {|aThread| aThread.join}
  end

  def test_upload_feature_dataset
    skip
    t = Time.now
    f = File.join DATA_DIR, "rat_feature_dataset.csv"
    d = Dataset.from_csv_file f
    assert_equal 458, d.features.size
    d.save
    #p "Upload: #{Time.now-t}"
    d2 = Dataset.find d.id
    t = Time.now
    assert_equal d.features.size, d2.features.size
    csv = CSV.read f
    csv.shift # remove header
    assert_empty d2.warnings
    assert_equal csv.size, d2.compounds.size 
    assert_equal csv.first.size-1, d2.features.size
    d2.compounds.each_with_index do |compound,i|
      row = csv[i]
      row.shift # remove compound
      assert_equal row, d2.data_entries[i]
    end
    #p "Dowload: #{Time.now-t}"
    assert_nil Dataset.find d.id
  end

end

