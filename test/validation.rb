require_relative "setup.rb"

class ValidationTest < MiniTest::Test

  def test_fminer_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::LazarFminerClassification.create dataset
    cv = ClassificationCrossValidation.create model
    refute_empty cv.validation_ids
    assert cv.accuracy > 0.8, "Crossvalidation accuracy lower than 0.8"
    assert cv.weighted_accuracy > cv.accuracy, "Weighted accuracy (#{cv.weighted_accuracy}) larger than unweighted accuracy(#{cv.accuracy}) "
  end

  def test_classification_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::LazarClassification.create dataset#, features
    cv = ClassificationCrossValidation.create model
    assert cv.accuracy > 0.7
    assert cv.weighted_accuracy > cv.accuracy, "Weighted accuracy should be larger than unweighted accuracy."
  end

  def test_regression_crossvalidation
    #dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.csv"
    model = Model::LazarRegression.create dataset
    cv = RegressionCrossValidation.create model
    #`inkview #{cv.plot}`
    #puts JSON.pretty_generate(cv.misclassifications)#.collect{|l| l.join ", "}.join "\n"
    #`inkview #{cv.plot}`
    assert cv.rmse < 30, "RMSE > 30"
    #assert cv.weighted_rmse < cv.rmse, "Weighted RMSE (#{cv.weighted_rmse}) larger than unweighted RMSE(#{cv.rmse}) "
    assert cv.mae < 12
    #assert cv.weighted_mae < cv.mae
  end

end
