require_relative "setup.rb"

class LazarClassificationTest < MiniTest::Test

  def test_classification_default
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D"
      },
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => 0.1
      },
      :prediction => {
        :method => "Algorithm::Classification.weighted_majority_vote",
      },
      :feature_selection => nil,
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::Lazar.create  training_dataset: training_dataset
    assert_kind_of Model::LazarClassification, model
    assert_equal algorithms, model.algorithms
    substance = training_dataset.substances[10]
    prediction = model.predict substance
    assert_equal "false", prediction[:value]
    [ {
      :compound => OpenTox::Compound.from_inchi("InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"),
      :prediction => "false",
    },{
      :compound => OpenTox::Compound.from_smiles("c1ccccc1NN"),
      :prediction => "false",
    } ].each do |example|
      prediction = model.predict example[:compound]
      assert_equal example[:prediction], prediction[:value]
    end

    compound = Compound.from_smiles "CCO"
    prediction = model.predict compound
    assert_equal "true", prediction[:value]
    assert_equal ["false"], prediction[:measurements]

    # make a dataset prediction
    compound_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.mini_log10.csv")
    prediction_dataset = model.predict compound_dataset
    assert_equal compound_dataset.compounds, prediction_dataset.compounds

    cid = prediction_dataset.compounds[7].id.to_s
    assert_equal "Could not find similar substances with experimental data in the training dataset.", prediction_dataset.predictions[cid][:warnings][0]
    expectations = ["Cannot create prediction: Only one similar compound in the training set.",
    "Could not find similar substances with experimental data in the training dataset."]
    prediction_dataset.predictions.each do |cid,pred|
      assert_includes expectations, pred[:warnings][0] if pred[:value].nil?
    end
    cid = Compound.from_smiles("CCOC(=O)N").id.to_s
    assert_match "excluded", prediction_dataset.predictions[cid][:info]
    # cleanup
    [training_dataset,model,compound_dataset,prediction_dataset].each{|o| o.delete}
  end
 
  def test_classification_parameters
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MACCS"
      },
      :similarity => {
        :min => 0.4
      },
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::Lazar.create training_dataset: training_dataset, algorithms: algorithms
    assert_kind_of Model::LazarClassification, model
    assert_equal "Algorithm::Classification.weighted_majority_vote", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.tanimoto", model.algorithms[:similarity][:method]
    assert_equal algorithms[:similarity][:min], model.algorithms[:similarity][:min]
    substance = training_dataset.substances[10]
    prediction = model.predict substance
    assert_equal "false", prediction[:value]
    assert_equal 4, prediction[:neighbors].size
  end

  def test_kazius
    t = Time.now
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"kazius.csv")
    t = Time.now
    model = Model::Lazar.create training_dataset: training_dataset
    t = Time.now
    2.times do
      compound = Compound.from_smiles("Clc1ccccc1NN")
      prediction = model.predict compound
      assert_equal "1", prediction[:value]
    end
    training_dataset.delete
  end

  def test_caret_classification
    skip
  end

  def test_fingerprint_chisq_feature_selection
    skip
  end

  def test_physchem_classification
    skip
  end
end
