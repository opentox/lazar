require_relative "setup.rb"

class PredictionModelTest < MiniTest::Test

  def test_prediction_model
    pm = Model::Prediction.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    [:endpoint,:species,:source].each do |p|
      refute_empty pm[p]
    end
    assert pm.classification?
    refute pm.regression?
    pm.crossvalidations.each do |cv|
      assert cv.accuracy > 0.75, "Crossvalidation accuracy (#{cv.accuracy}) should be larger than 0.75. This may happen due to an unfavorable training/test set split."
    end
    prediction = pm.predict Compound.from_smiles("CCCC(NN)C")
    assert_equal "true", prediction[:value]
    pm.delete
  end
end
