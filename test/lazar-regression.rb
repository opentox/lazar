require_relative "setup.rb"

class LazarRegressionTest < MiniTest::Test

  def test_weighted_average
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    model = Model::LazarRegression.create training_dataset, {:neighbor_algorithm_parameters => {:min_sim => 0}}
    compound = Compound.from_smiles "CC(C)(C)CN"
    prediction = model.predict compound
    assert_equal 7.2, prediction[:value].round(1)
    assert_equal 88, prediction[:neighbors].size
  end

  def test_mpd_fingerprints
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    model = Model::LazarRegression.create training_dataset
    model.neighbor_algorithm_parameters[:type] = "MP2D"
    compound = Compound.from_smiles "CCCSCCSCC"
    prediction = model.predict compound
    assert_equal 0.04, prediction[:value].round(2)
    assert_equal 3, prediction[:neighbors].size
  end

  def test_local_pls_regression
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    model = Model::LazarRegression.create training_dataset
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    p prediction
    model.update(:prediction_algorithm => "OpenTox::Algorithm::Regression.local_pls_regression")
    prediction = model.predict compound
    p prediction
    #assert_equal 13.6, prediction[:value].round(1)
    #assert_equal 0.83, prediction[:confidence].round(2)
    #assert_equal 1, prediction[:neighbors].size
  end

end
