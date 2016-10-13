require_relative "setup.rb"

class LazarRegressionTest < MiniTest::Test

  def test_weighted_average
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :similarity => {
        :min => 0
      },
      :prediction => {
        :method => "Algorithm::Regression.weighted_average",
      },
    }
    model = Model::Lazar.create training_dataset: training_dataset, algorithms: algorithms
    compound = Compound.from_smiles "CC(C)(C)CN"
    prediction = model.predict compound
    assert_equal -0.86, prediction[:value].round(2)
    assert_equal 88, prediction[:neighbors].size
  end

  def test_mpd_fingerprints
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :descriptors => [ "MP2D" ]
    }
    model = Model::Lazar.create training_dataset: training_dataset, algorithms: algorithms
    compound = Compound.from_smiles "CCCSCCSCC"
    prediction = model.predict compound
    assert_equal 3, prediction[:neighbors].size
    assert_equal 1.37, prediction[:value].round(2)
  end

  def test_local_fingerprint_regression
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    model = Model::Lazar.create training_dataset: training_dataset
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    refute_nil prediction[:value]
    refute_nil prediction[:prediction_interval]
    refute_empty prediction[:neighbors]
  end

  def test_local_physchem_regression
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :descriptors => ["PhysChem::OPENBABEL"],
      :similarity => {
        :method => "Algorithm::Similarity.weighted_cosine",
        :min => 0.5
      },
    }
    model = Model::Lazar.create(training_dataset:training_dataset, algorithms:algorithms)
    p model
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    refute_nil prediction[:value]
  end

  def test_local_physchem_regression_with_feature_selection
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :descriptors => {
        :method => "calculated_properties",
        :types => ["OPENBABEL"]
      },
      :similarity => {
        :method => "Algorithm::Similarity.weighted_cosine",
        :min => 0.5
      },
      :feature_selection => {
        :method => "Algorithm::FeatureSelection.correlation_filter",
      },
    }
    model = Model::Lazar.create(training_dataset.features.first, training_dataset, algorithms)
    p model
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    refute_nil prediction[:value]
  end

  def test_local_physchem_classification
    skip
  end

end
