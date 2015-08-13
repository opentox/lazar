require_relative "setup.rb"

class LazarExtendedTest < MiniTest::Test

  def test_lazar_bbrc_ham_minfreq
    dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = OpenTox::Model::Lazar.create dataset, OpenTox::Algorithm::Fminer.bbrc(dataset, :min_frequency => 5)
    feature_dataset = OpenTox::Dataset.find model.feature_dataset_id
    assert_equal dataset.compounds.size, feature_dataset.compounds.size
    assert_equal 41, feature_dataset.features.size
    assert_equal 'N-C=N', feature_dataset.features.first.smarts
    compound = OpenTox::Compound.from_inchi("InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H")
    prediction = model.predict compound
    assert_equal "false", prediction[:value]
    assert_equal 0.12380952380952381, prediction[:confidence]
    dataset.delete
    model.delete
    feature_dataset.delete
  end

  def test_lazar_bbrc_large_ds
    # TODO fminer crashes with these settings
    skip "it seems that fminer aborts without further notice"
    dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"multi_cell_call_no_dup.csv")
    feature_dataset = OpenTox::Algorithm::Fminer.bbrc dataset#, :min_frequency => 15)
    model = OpenTox::Model::Lazar.create dataset, feature_dataset
    model.save
    p model.id
    feature_dataset = OpenTox::CalculatedDataset.find model.feature_dataset_id
    assert_equal dataset.compounds.size, feature_dataset.compounds.size
    assert_equal 52, feature_dataset.features.size
    assert_equal '[#17&A]-[#6&A]', feature_dataset.features.first.title
    compound = OpenTox::Compound.from_inchi("InChI=1S/C10H9NO2S/c1-8-2-4-9(5-3-8)13-6-10(12)11-7-14/h2-5H,6H2,1H3")
    prediction_dataset = model.predict compound
    prediction = prediction_dataset.data_entries.first
    assert_in_delta 0.025, prediction[:confidence], 0.001
    #assert_equal 0.025885845574483608, prediction[:confidence]
    # with compound change in training_dataset see:
    # https://github.com/opentox/opentox-test/commit/0e78c9c59d087adbd4cc58bab60fb29cbe0c1da0
    #assert_equal 0.02422364949075546, prediction[:confidence]
    dataset.delete
    model.delete
    feature_dataset.delete
    prediction_dataset.delete
  end

  def test_lazar_kazius
    t = Time.now
    dataset = Dataset.from_csv_file File.join(DATA_DIR,"kazius.csv")
    p "Dataset upload: #{Time.now-t}"
    t = Time.now
    feature_dataset = Algorithm::Fminer.bbrc(dataset, :min_frequency => 100)
    p "Feature mining: #{Time.now-t}"
    t = Time.now
    assert_equal feature_dataset.compounds.size, dataset.compounds.size
    model = Model::Lazar.create dataset, feature_dataset
=begin
=end
    #model = Model::Lazar.find('55bcf5bf7a7838381200017e')
    #p model.id
    #prediction_times = []
    2.times do
      compound = Compound.from_smiles("Clc1ccccc1NN")
      prediction = model.predict compound
      assert_equal "1", prediction[:value]
      assert_in_delta 0.019858401199860445, prediction[:confidence], 0.001
    end
    #dataset.delete
    #feature_dataset.delete
  end

end
