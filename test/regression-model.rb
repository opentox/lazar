require_relative "setup.rb"

class LazarRegressionTest < MiniTest::Test

  def test_default_regression
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D"
      },
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => [0.5,0.2]
      },
      :prediction => {
        :method => "Algorithm::Caret.rf",
      },
      :feature_selection => nil,
    }
    training_dataset = Dataset.from_csv_file File.join(Download::DATA, "Acute_toxicity-Fathead_minnow.csv")
    model = Model::Lazar.create  training_dataset: training_dataset
    assert_kind_of Model::LazarRegression, model
    assert_equal algorithms, model.algorithms
    substance = training_dataset.substances[145]
    prediction = model.predict substance
    assert_includes prediction[:prediction_interval][0]..prediction[:prediction_interval][1], prediction[:measurements].median, "This assertion assures that measured values are within the prediction interval. It may fail in 5% of the predictions."
    substance = Compound.from_smiles "c1ccc(cc1)Oc1ccccc1"
    prediction = model.predict substance
    refute_nil prediction[:value]
    refute_nil prediction[:prediction_interval]
    refute_empty prediction[:neighbors]
  end

  def test_weighted_average
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :similarity => {
        :min => [0,0]
      },
      :prediction => {
        :method => "Algorithm::Regression.weighted_average",
      },
    }
    model = Model::Lazar.create training_dataset: training_dataset, algorithms: algorithms
    compound = Compound.from_smiles "CC(C)(C)CN"
    prediction = model.predict compound
    assert_equal -0.86, prediction[:value].round(2)
    assert_equal model.substance_ids.size, prediction[:neighbors].size
  end

  def test_mpd_fingerprints
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D"
      },
    }
    model = Model::Lazar.create training_dataset: training_dataset, algorithms: algorithms
    compound = Compound.from_smiles "CCCSCCSCC"
    prediction = model.predict compound
    assert_equal 3, prediction[:neighbors].size
    assert prediction[:value].round(2) > 1.37, "Prediction value (#{prediction[:value].round(2)}) should be larger than 1.37."
  end

  def test_local_physchem_regression
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :descriptors => {
        :method => "calculate_properties",
        :features => PhysChem.openbabel_descriptors,
      },
      :similarity => {
        :method => "Algorithm::Similarity.weighted_cosine",
        :min => [0.5,0.1]
      },
    }
    model = Model::Lazar.create(training_dataset:training_dataset, algorithms:algorithms)
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    refute_nil prediction[:value]
  end

  def test_local_physchem_regression_with_feature_selection
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :descriptors => {
        :method => "calculate_properties",
        :features => PhysChem.openbabel_descriptors,
      },
      :similarity => {
        :method => "Algorithm::Similarity.weighted_cosine",
        :min => [0.5,0.1]
      },
      :feature_selection => {
        :method => "Algorithm::FeatureSelection.correlation_filter",
      },
    }
    model = Model::Lazar.create(training_dataset:training_dataset, algorithms:algorithms)
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    refute_nil prediction[:value]
  end

  def test_unweighted_cosine_physchem_regression
    algorithms = {
      :descriptors => {
        :method => "calculate_properties",
        :features => PhysChem.openbabel_descriptors,
      },
      :similarity => {
        :method => "Algorithm::Similarity.cosine",
      }
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
    assert_kind_of Model::LazarRegression, model
    assert_equal "Algorithm::Caret.rf", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.cosine", model.algorithms[:similarity][:method]
    assert_equal 0.5, model.algorithms[:similarity][:min].first
    algorithms[:descriptors].delete :features
    assert_equal algorithms[:descriptors], model.algorithms[:descriptors]
    prediction = model.predict training_dataset.substances[10]
    refute_nil prediction[:value]
  end

  def test_regression_with_feature_selection
    algorithms = {
      :feature_selection => {
        :method => "Algorithm::FeatureSelection.correlation_filter",
      },
    }
    training_dataset = Dataset.from_csv_file File.join(Download::DATA, "Acute_toxicity-Fathead_minnow.csv")
    model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
    assert_kind_of Model::LazarRegression, model
    assert_equal "Algorithm::Caret.rf", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.tanimoto", model.algorithms[:similarity][:method]
    assert_equal 0.5, model.algorithms[:similarity][:min].first
    assert_equal algorithms[:feature_selection][:method], model.algorithms[:feature_selection][:method]
    prediction = model.predict training_dataset.substances[145]
    refute_nil prediction[:value]
  end

  def test_regression_parameters
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D"
      },
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => [0.3,0.1]
      },
      :prediction => {
        :method => "Algorithm::Regression.weighted_average",
      },
      :feature_selection => nil,
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
    assert_kind_of Model::LazarRegression, model
    assert_equal "Algorithm::Regression.weighted_average", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.tanimoto", model.algorithms[:similarity][:method]
    assert_equal algorithms[:similarity][:min], model.algorithms[:similarity][:min]
    assert_equal algorithms[:prediction][:parameters], model.algorithms[:prediction][:parameters]
    substance = training_dataset.substances[10]
    prediction = model.predict substance
    assert_equal 0.83, prediction[:value].round(2)
  end

  def test_dataset_prediction
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create training_dataset: training_dataset
    result = model.predict training_dataset
    assert_kind_of Dataset, result
    assert_equal 6, result.features.size
    assert_equal 88, result.compounds.size
    assert_equal [1.95], result.values(result.compounds.first, result.bioactivity_features[0]).collect{|v| v.round(2)}
    assert_equal [1.37], result.values(result.compounds[6], result.bioactivity_features[0]).collect{|v| v.round(2)}
    assert_equal [1.79], result.values(result.compounds[6], result.prediction_features[0]).collect{|v| v.round(2)}
    assert_equal [1.84,1.73], result.values(result.compounds[7], result.bioactivity_features[0]).collect{|v| v.round(2)}
    assert_match /Low/i, result.predictions[result.compounds[6]][:confidence]
  end

end
