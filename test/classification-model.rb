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
        :min => 0.5
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
    [ {
      :compound => OpenTox::Compound.from_smiles("OCC(CN(CC(O)C)N=O)O"),
      :prediction => "false",
    },{
      :compound => OpenTox::Compound.from_smiles("O=CNc1scc(n1)c1ccc(o1)[N+](=O)[O-]"),
      :prediction => "true",
    } ].each do |example|
      prediction = model.predict example[:compound]
      assert_equal example[:prediction], prediction[:value]
    end

    # make a dataset prediction
    compound_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"multi_cell_call.csv")
    prediction_dataset = model.predict compound_dataset
    puts prediction_dataset.to_csv
    assert_equal compound_dataset.compounds.size, prediction_dataset.compounds.size
    c = Compound.from_smiles "CC(CN(CC(O)C)N=O)O"
    prediction_feature = prediction_dataset.features.select{|f| f.class == NominalLazarPrediction}[0]
    assert_equal ["true"], prediction_dataset.values(c, prediction_feature)
    p_true = LazarPredictionProbability.find_by(:name => "true")
    p_false = LazarPredictionProbability.find_by(:name => "false")
    p p_true
    assert_equal [0.7], prediction_dataset.values(c,p_true)
    assert_equal [0.0], prediction_dataset.values(c,p_false)
    assert_equal 0.0, p_false

#    cid = prediction_dataset.compounds[7].id.to_s
#    assert_equal "Could not find similar substances with experimental data in the training dataset.", prediction_dataset.predictions[cid][:warnings][0]
#    expectations = ["Cannot create prediction: Only one similar compound in the training set.",
#    "Could not find similar substances with experimental data in the training dataset."]
#    prediction_dataset.predictions.each do |cid,pred|
#      assert_includes expectations, pred[:warnings][0] if pred[:value].nil?
#    end
#    cid = Compound.from_smiles("CCOC(=O)N").id.to_s
#    assert_match "excluded", prediction_dataset.predictions[cid][:info]
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

  def test_dataset_prediction
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::Lazar.create training_dataset: training_dataset
    result = model.predict training_dataset
    puts result.to_csv
    assert_kind_of Dataset, result
    assert 3, result.features.size
    assert 8, result.compounds.size
    assert_equal ["true"], result.values(result.compounds.first, result.features[0])
    assert_equal [0.65], result.values(result.compounds.first, result.features[1])
    assert_equal [0], result.values(result.compounds.first, result.features[2]) # classification returns nil, check if 
  end

  def test_carcinogenicity_rf_classification
    skip "Caret rf may run into a (endless?) loop for some compounds."
    dataset = Dataset.from_csv_file "#{DATA_DIR}/multi_cell_call.csv"
    algorithms = {
      :prediction => {
        :method => "Algorithm::Caret.rf",
      },
    }
    model = Model::Lazar.create training_dataset: dataset, algorithms: algorithms
    substance = Compound.from_smiles "[O-]S(=O)(=O)[O-].[Mn+2].O"
    prediction = model.predict substance
    p prediction
    
  end

  def test_rf_classification
    skip "Caret rf may run into a (endless?) loop for some compounds."
    algorithms = {
      :prediction => {
        :method => "Algorithm::Caret.rf",
      },
    }
    training_dataset = Dataset.from_sdf_file File.join(DATA_DIR,"cas_4337.sdf")
    model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
    #p model.id.to_s
    #model = Model::Lazar.find "5bbb4c0cca626909f6c8a924"
    assert_kind_of Model::LazarClassification, model
    assert_equal algorithms[:prediction][:method], model.algorithms["prediction"]["method"]
    substance = Compound.from_smiles "Clc1ccc(cc1)C(=O)c1ccc(cc1)OC(C(=O)O)(C)C"
    prediction = model.predict substance
    assert_equal  51, prediction[:neighbors].size
    assert_equal "nonmutagen", prediction[:value]
    assert_equal 0.1, prediction[:probabilities]["mutagen"].round(1)
    assert_equal 0.9, prediction[:probabilities]["nonmutagen"].round(1)
  end

end
