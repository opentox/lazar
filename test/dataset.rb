# TODO; check compound/data_entry sequences with missing and duplicated values

require_relative "setup.rb"

class DatasetTest < MiniTest::Test

  def test_all
    d1 = Dataset.new 
    d1.save
    datasets = Dataset.all 
    assert_equal Dataset, datasets.first.class
    d1.delete
  end
=begin
  #TODO
  def test_create_without_features_csv
    d = Dataset.from_csv_file File.join(DATA_DIR,"batch_prediction.csv")
    assert_equal Dataset, d.class
    refute_nil d.id
    dataset = Dataset.find d.id
    #p dataset.compounds
    assert_equal 24, d.compounds.size.to_i
    d.delete
  end
=end
  def test_create_empty
    d = Dataset.new
    assert_equal Dataset, d.class
    refute_nil d.id
    assert_kind_of BSON::ObjectId, d.id
  end

  def test_client_create
    d = Dataset.new
    assert_equal Dataset, d.class
    d.name = "Create dataset test"

    # features not set
    # << operator was removed for efficiency reasons (CH)
    #assert_raises BadRequestError do
    #  d << [Compound.from_smiles("c1ccccc1NN"), 1,2]
    #end

    # add data entries
    d.features = ["test1", "test2"].collect do |title|
      f = Feature.new 
      f.name = title
      f.numeric = true
      f.save
      f
    end

    # wrong feature size
    # << operator was removed for efficiency reasons (CH)
    #assert_raises BadRequestError do
    #  d << [Compound.from_smiles("c1ccccc1NN"), 1,2,3]
    #end
    
    # manual low-level insertions without consistency checks for runtime efficiency
    data_entries = []
    d.compound_ids << Compound.from_smiles("c1ccccc1NN").id
    data_entries << [1,2]
    d.compound_ids << Compound.from_smiles("CC(C)N").id
    data_entries << [4,5]
    d.compound_ids << Compound.from_smiles("C1C(C)CCCC1").id
    data_entries << [6,7]
    d.data_entries = data_entries
    assert_equal 3, d.compounds.size
    assert_equal 2, d.features.size
    assert_equal [[1,2],[4,5],[6,7]], d.data_entries
    d.save_all
    # check if dataset has been saved correctly
    new_dataset = Dataset.find d.id
    assert_equal 3, new_dataset.compounds.size
    assert_equal 2, new_dataset.features.size
    assert_equal [[1,2],[4,5],[6,7]], new_dataset.data_entries
    d.delete
    assert_nil Dataset.find d.id
    assert_nil Dataset.find new_dataset.id
  end

  def test_dataset_accessors
    d = Dataset.from_csv_file "#{DATA_DIR}/multicolumn.csv"
    # create empty dataset
    new_dataset = Dataset.find d.id
    # get metadata
    assert_match "multicolumn.csv",  new_dataset.source
    assert_equal "multicolumn",  new_dataset.name
    # get features
    assert_equal 6, new_dataset.features.size
    assert_equal 7, new_dataset.compounds.size
    assert_equal ["1", nil, "false", nil, nil, 1.0], new_dataset.data_entries.last
    d.delete
  end

  def test_create_from_file
    d = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.mini.csv")
    assert_equal Dataset, d.class
    refute_nil d.warnings
    assert_match "EPAFHM.mini.csv",  d.source
    assert_equal "EPAFHM.mini.csv",  d.name
    d.delete 
    #assert_equal false, URI.accessible?(d.uri)
  end

  def test_create_from_file_with_wrong_smiles_compound_entries
    d = Dataset.from_csv_file File.join(DATA_DIR,"wrong_dataset.csv")
    refute_nil d.warnings
    assert_match /2|3|4|5|6|7|8/, d.warnings.join
    d.delete
  end

  def test_multicolumn_csv
    d = Dataset.from_csv_file "#{DATA_DIR}/multicolumn.csv"
    refute_nil d.warnings
    assert d.warnings.grep(/Duplicate compound/)  
    assert d.warnings.grep(/3, 5/)  
    assert_equal 6, d.features.size
    assert_equal 7, d.compounds.size
    assert_equal 5, d.compounds.collect{|c| c.inchi}.uniq.size
    assert_equal [["1", "1", "true", "true", "test", 1.1], ["1", "2", "false", "7.5", "test", 0.24], ["1", "3", "true", "5", "test", 3578.239], ["0", "4", "false", "false", "test", -2.35], ["1", "2", "true", "4", "test_2", 1], ["1", "2", "false", "false", "test", -1.5], ["1", nil, "false", nil, nil, 1.0]], d.data_entries
    assert_equal "c1ccc[nH]1,1,,false,,,1.0", d.to_csv.split("\n")[7]
    csv = CSV.parse(d.to_csv)
    original_csv = CSV.read("#{DATA_DIR}/multicolumn.csv")
    csv.shift
    original_csv.shift
    csv.each_with_index do |row,i|
      compound = Compound.from_smiles row.shift
      original_compound = Compound.from_smiles original_csv[i].shift
      assert_equal original_compound.inchi, compound.inchi
      row.each_with_index do |v,j|
        if v.numeric?
          assert_equal original_csv[i][j].strip.to_f, row[j].to_f
        else
          assert_equal original_csv[i][j].strip, row[j].to_s
        end
      end
    end
    d.delete 
  end

  def test_from_csv
    d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    assert_equal Dataset, d.class
    assert_equal 1, d.features.size
    assert_equal 85, d.compounds.size
    assert_equal 85, d.data_entries.size
    csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.csv")
    csv.shift
    assert_equal csv.collect{|r| r[1]}, d.data_entries.flatten
    d.delete 
    #assert_equal false, URI.accessible?(d.uri)
  end

  def test_from_csv_classification
    ["int", "float", "string"].each do |mode|
      d = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.mini.bool_#{mode}.csv"
      csv = CSV.read("#{DATA_DIR}/hamster_carcinogenicity.mini.bool_#{mode}.csv")
      csv.shift
      entries = d.data_entries.flatten
      csv.each_with_index do |r, i|
        assert_equal r[1].to_s, entries[i]
      end
      d.delete 
    end
  end

  def test_from_csv2
    File.open("#{DATA_DIR}/temp_test.csv", "w+") { |file| file.write("SMILES,Hamster\nCC=O,true\n ,true\nO=C(N),true") }
    dataset = Dataset.from_csv_file "#{DATA_DIR}/temp_test.csv"
    assert_equal "Cannot parse SMILES compound ' ' at position 3, all entries are ignored.",  dataset.warnings.join
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

  def test_create_from_file
    d = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.mini.csv")
    assert_equal Dataset, d.class
    refute_nil d.warnings
    assert_match /row 13/, d.warnings.join
    assert_match "EPAFHM.mini.csv",  d.source
    assert_equal 1, d.features.size
    feature = d.features.first
    assert_kind_of NumericBioAssay, feature
    assert_equal 0.0113, d.data_entries[0][0]
    assert_equal 0.00323, d.data_entries[5][0]
    d2 = Dataset.find d.id
    assert_equal 0.0113, d2.data_entries[0][0]
    assert_equal 0.00323, d2.data_entries[5][0]
  end

end

