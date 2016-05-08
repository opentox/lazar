require_relative "setup.rb"

class LazarRegressionTest < MiniTest::Test

  def test_weighted_average
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    model = Model::LazarRegression.create training_dataset.features.first, training_dataset, {:neighbor_algorithm_parameters => {:min_sim => 0}, :prediction_algorithm => "OpenTox::Algorithm::Regression.local_weighted_average"}
    compound = Compound.from_smiles "CC(C)(C)CN"
    prediction = model.predict compound
    assert_equal -0.86, prediction[:value].round(2)
    assert_equal 88, prediction[:neighbors].size
  end

  def test_mpd_fingerprints
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    model = Model::LazarRegression.create training_dataset.features.first, training_dataset
    model.neighbor_algorithm_parameters[:type] = "MP2D"
    compound = Compound.from_smiles "CCCSCCSCC"
    prediction = model.predict compound
    assert_equal 1.37, prediction[:value].round(2)
    assert_equal 3, prediction[:neighbors].size
  end

  def test_local_fingerprint_regression
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    model = Model::LazarRegression.create(training_dataset.features.first, training_dataset, :prediction_algorithm => "OpenTox::Algorithm::Regression.local_fingerprint_regression")
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    refute_nil prediction[:value]
    refute_nil prediction[:prediction_interval]
    refute_empty prediction[:neighbors]
  end

  def test_local_physchem_regression
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    model = Model::LazarRegression.create(training_dataset.features.first, training_dataset, :prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression")
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    refute_nil prediction[:value]
  end

end
