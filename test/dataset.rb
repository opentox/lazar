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
    d1.delete
  end

  # real datasets

  def test_upload_hamster
    d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    assert_equal Dataset, d.class
    assert_equal 1, d.features.size
    assert_equal 85, d.compounds.size
    csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.csv")
    csv.shift
    csv.each do |row|
      c = Compound.from_smiles row.shift
      assert_equal row, c.toxicities[d.features.first.id.to_s][d.id.to_s]
    end
    d.delete 
  end

  def test_upload_kazius
    f = File.join DATA_DIR, "kazius.csv"
    d = OpenTox::Dataset.from_csv_file f 
    csv = CSV.read f
    assert_equal csv.size-1, d.compounds.size
    assert_equal csv.first.size-1, d.features.size
    assert_empty d.warnings
    #  493 COC1=C(C=C(C(=C1)Cl)OC)Cl,1
    c = d.compounds[491]
    assert_equal c.smiles, "COc1cc(Cl)c(cc1Cl)OC"
    assert_equal c.toxicities[d.feature_ids.first.to_s][d.id.to_s][0], "1"
    d.delete
  end

  def test_upload_multicell
    duplicates = [
      "InChI=1S/C6HCl5O/c7-1-2(8)4(10)6(12)5(11)3(1)9/h12H",
      "InChI=1S/C12H8Cl6O/c13-8-9(14)11(16)5-3-1-2(6-7(3)19-6)4(5)10(8,15)12(11,17)18/h2-7H,1H2",
      "InChI=1S/C2HCl3/c3-1-2(4)5/h1H",
      "InChI=1S/C4H5Cl/c1-3-4(2)5/h3H,1-2H2",
      "InChI=1S/C4H7Cl/c1-4(2)3-5/h1,3H2,2H3",
      "InChI=1S/C8H14O4/c1-5-4-8(11-6(2)9)12-7(3)10-5/h5,7-8H,4H2,1-3H3",
      "InChI=1S/C19H30O5/c1-3-5-7-20-8-9-21-10-11-22-14-17-13-19-18(23-15-24-19)12-16(17)6-4-2/h12-13H,3-11,14-15H2,1-2H3",
    ].collect{|inchi| Compound.from_inchi(inchi).smiles}
    errors = ['O=P(H)(OC)OC', 'C=CCNN.HCl' ]
    f = File.join DATA_DIR, "multi_cell_call.csv"
    d = OpenTox::Dataset.from_csv_file f 
    csv = CSV.read f
    assert_equal true, d.features.first.nominal
    assert_equal csv.size-1-errors.size, d.compounds.size
    assert_equal csv.first.size-1, d.features.size
    puts d.warnings.to_yaml
    errors.each do |smi|
      refute_empty d.warnings.grep %r{#{Regexp.escape(smi)}}
    end
    duplicates.each do |smi|
      refute_empty d.warnings.grep %r{#{Regexp.escape(smi)}}
    end
    d.delete
  end

  def test_upload_isscan
    f = File.join DATA_DIR, "ISSCAN-multi.csv"
    d = OpenTox::Dataset.from_csv_file f 
    csv = CSV.read f
    assert_equal csv.size-1, d.compounds.size
    assert_equal csv.first.size-1, d.features.size
    d.delete
  end

  def test_upload_epafhm
    f = File.join DATA_DIR, "EPAFHM_log10.csv"
    d = OpenTox::Dataset.from_csv_file f
    assert_equal Dataset, d.class
    csv = CSV.read f
    assert_equal csv.size-1, d.compounds.size
    assert_equal csv.first.size-1, d.features.size
    assert_match "EPAFHM_log10.csv",  d.source
    assert_equal "EPAFHM_log10",  d.name
    refute_nil d.warnings
    #p d.warnings
    #assert_equal 74, d.warnings.size
    feature = d.features.first
    assert_kind_of NumericFeature, feature
    assert_match /row 13/, d.warnings.join
    assert_equal -Math.log10(0.0113), d.compounds.first.toxicities[feature.id.to_s][d.id.to_s].first
    assert_equal -Math.log10(0.00323), d.compounds[5].toxicities[feature.id.to_s][d.id.to_s].first
    d2 = Dataset.find d.id
    assert_equal -Math.log10(0.0113), d2.compounds[0].toxicities[feature.id.to_s][d.id.to_s].first
    assert_equal -Math.log10(0.00323), d2.compounds[5].toxicities[feature.id.to_s][d.id.to_s].first
    d.delete
  end

  # batch predictions

  def test_create_without_features_smiles_and_inchi
    ["smiles", "inchi"].each do |type|
      d = Dataset.from_csv_file File.join(DATA_DIR,"batch_prediction_#{type}_small.csv")
      assert_equal Dataset, d.class
      refute_nil d.id
      dataset = Dataset.find d.id
      assert_equal 3, d.compounds.size.to_i
      d.delete
    end
  end

  # dataset operations

  def test_folds
    dataset = Dataset.from_csv_file File.join(DATA_DIR,"loael.csv")
    dataset.folds(10).each do |fold|
      fold.each do |d|
        assert_operator d.compounds.size, :>=, d.compounds.uniq.size
      end
      assert_operator fold[0].compounds.size, :>=, fold[1].compounds.size
      assert_equal dataset.substance_ids.size, fold.first.substance_ids.size + fold.last.substance_ids.size
      assert_empty (fold.first.substance_ids & fold.last.substance_ids)
    end
  end

  # serialisation

  def test_to_csv
    d = Dataset.from_csv_file "#{DATA_DIR}/multicolumn.csv"
    refute_nil d.warnings
    assert d.warnings.grep(/Duplicate compound/)  
    assert d.warnings.grep(/3, 5/)  
    assert_equal 6, d.features.size
    assert_equal 5, d.compounds.uniq.size
    assert_equal 5, d.compounds.collect{|c| c.inchi}.uniq.size
    csv = CSV.parse(d.to_csv)
    original_csv = CSV.read("#{DATA_DIR}/multicolumn.csv")
    csv.shift
    original_csv.shift
    original = {}
    original_csv.each do |row|
      c = Compound.from_smiles row.shift.strip
      original[c.inchi] = row.collect{|v| v.strip}
    end
    serialized = {}
    csv.each do |row|
      c = Compound.from_smiles row.shift
      serialized[c.inchi] = row
    end
    original.each do |inchi,row|
      row.each_with_index do |v,i|
        if v.numeric?
          assert_equal v.to_f, serialized[inchi][i].to_f
        else
          assert_equal v, serialized[inchi][i]
        end
      end

    end
    d.delete 
  end

  # special cases/details

  def test_dataset_accessors
    d = Dataset.from_csv_file "#{DATA_DIR}/multicolumn.csv"
    # create empty dataset
    new_dataset = Dataset.find d.id
    # get metadata
    assert_match "multicolumn.csv",  new_dataset.source
    assert_equal "multicolumn",  new_dataset.name
    # get features
    assert_equal 6, new_dataset.features.size
    assert_equal 5, new_dataset.compounds.uniq.size
    de = new_dataset.compounds.last.toxicities
    fid = new_dataset.features.first.id.to_s
    assert_equal ["1"], de[fid][d.id.to_s]
    fid = new_dataset.features.last.id.to_s
    assert_equal [1.0], de[fid][d.id.to_s]
    fid = new_dataset.features[2].id.to_s
    assert_equal ["false"], de[fid][d.id.to_s]
    d.delete
  end

  def test_create_from_file_with_wrong_smiles_compound_entries
    d = Dataset.from_csv_file File.join(DATA_DIR,"wrong_dataset.csv")
    refute_nil d.warnings
    assert_match /2|3|4|5|6|7|8/, d.warnings.join
    d.delete
  end

  def test_from_csv_classification
    ["int", "float", "string"].each do |mode|
      d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.mini.bool_#{mode}.csv"
      csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.mini.bool_#{mode}.csv")
      csv.shift
      csv.each do |row|
        c = Compound.from_smiles row.shift
        assert_equal row, c.toxicities[d.feature_ids.first.to_s][d.id.to_s]
      end
      d.delete 
    end
  end

  def test_from_csv2
    File.open("#{DATA_DIR}/temp_test.csv", "w+") { |file| file.write("SMILES,Hamster\nCC=O,true\n ,true\nO=C(N),true") }
    dataset = Dataset.from_csv_file "#{DATA_DIR}/temp_test.csv"
    assert_equal "Cannot parse SMILES compound '' at position 3, all entries are ignored.",  dataset.warnings.join
    File.delete "#{DATA_DIR}/temp_test.csv"
    dataset.features.each{|f| feature = Feature.find f.id; feature.delete}
    dataset.delete
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
    datasets.each{|d| d.delete}
  end

  # skips, may be removed in the future

  def test_simultanous_upload
    skip
    threads = []
    3.times do |t|
      threads << Thread.new(t) do |up|
        d = OpenTox::Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
        assert_equal OpenTox::Dataset, d.class
        assert_equal 1, d.features.size
        assert_equal 85, d.compounds.size
        csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.csv")
        csv.shift
        csv.each do |row|
          c = Compound.from_smiles(row.shift)
          p row
          p c.toxicities
          p d.feature_ids.first.to_s
          assert_equal row, c.toxicities[d.feature_ids.first.to_s][d.id.to_s]
        end
        d.delete 
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
    d2.delete
    assert_nil Dataset.find d.id
  end

  def test_client_create
    skip
    d = Dataset.new
    assert_equal Dataset, d.class
    d.name = "Create dataset test"

    # add data entries
    features = ["test1", "test2"].collect do |title|
      f = Feature.new 
      f.name = title
      f.numeric = true
      f.save
      f
    end
    
    # manual low-level insertions without consistency checks for runtime efficiency
    compounds = ["c1ccccc1NN", "CC(C)N", "C1C(C)CCCC1"].collect do |smi|
      Compound.from_smiles smi
    end
    data_entries = []
    data_entries << [1,2]
    data_entries << [4,5]
    data_entries << [6,7]
    compounds.each_with_index do |c,i|
      features.each_with_index do |f,j|
        d.substance_ids << c.id
        d.feature_ids << f.id
        c.toxicities[f.id.to_s] = data_entries[i][j]
      end
    end

    assert_equal 3, d.compounds.size
    assert_equal 2, d.features.size
    #assert_equal [[1,2],[4,5],[6,7]], d.data_entries
    d.save
    # check if dataset has been saved correctly
    new_dataset = Dataset.find d.id
    assert_equal 3, new_dataset.compounds.size
    assert_equal 2, new_dataset.features.size
    new_dataset.compounds.each_with_index do |c,i|
      new_dataset.features.each_with_index do |f,j|
        assert_equal data_entries[i][j], c.toxicities[f.id.to_s].first
      end
    end
    d.delete
    assert_nil Dataset.find d.id
    assert_nil Dataset.find new_dataset.id
  end

end

