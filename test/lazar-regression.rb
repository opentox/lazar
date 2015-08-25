require_relative "setup.rb"

class LazarRegressionTest < MiniTest::Test

  def test_weighted_average
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    model = Model::LazarRegression.create training_dataset
    compound = Compound.from_smiles "CC(C)(C)CN"
    prediction = model.predict compound
    assert_equal 13.6, prediction[:value].round(1)
    assert_equal 0.83, prediction[:confidence].round(2)
    assert_equal 1, prediction[:neighbors].size
  end

  def test_local_linear_regression
    skip
    training_dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    model = Model::LazarRegression.create training_dataset
    model.update(:prediction_algorithm => "OpenTox::Algorithm::Regression.local_linear_regression")
    compound = Compound.from_smiles "NC(=O)OCCC"
    prediction = model.predict compound
    p prediction
    #assert_equal 13.6, prediction[:value].round(1)
    #assert_equal 0.83, prediction[:confidence].round(2)
    #assert_equal 1, prediction[:neighbors].size
  end

end
