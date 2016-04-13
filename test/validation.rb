require_relative "setup.rb"

class ValidationTest < MiniTest::Test

  # defaults
  
  def test_default_classification_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::LazarClassification.create dataset
    cv = ClassificationCrossValidation.create model
    assert cv.accuracy > 0.7, "Accuracy (#{cv.accuracy}) should be larger than 0.7, this may occur due to an unfavorable training/test set split"
  end

  def test_default_regression_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    model = Model::LazarRegression.create dataset
    cv = RegressionCrossValidation.create model
    assert cv.rmse < 1.5, "RMSE #{cv.rmse} should be larger than 1.5, this may occur due to an unfavorable training/test set split"
    assert cv.mae < 1, "MAE #{cv.mae} should be larger than 1, this may occur due to an unfavorable training/test set split"
  end

  # parameters

  def test_classification_crossvalidation_parameters
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    params = {
        :training_dataset_id => dataset.id,
      :neighbor_algorithm_parameters => {
        :min_sim => 0.3,
        :type => "FP3"
      }
    }
    model = Model::LazarClassification.create dataset, params
    model.save
    cv = ClassificationCrossValidation.create model
    params = model.neighbor_algorithm_parameters
    params.delete :training_dataset_id
    params = Hash[params.map{ |k, v| [k.to_s, v] }] # convert symbols to string

    cv.validations.each do |validation|
      validation_params = validation.model.neighbor_algorithm_parameters
      validation_params.delete "training_dataset_id"
      assert_equal params, validation_params
    end
  end
  
  def test_regression_crossvalidation_params
    dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    params = {
      :prediction_algorithm => "OpenTox::Algorithm::Regression.local_weighted_average",
      :neighbor_algorithm => "fingerprint_neighbors",
      :neighbor_algorithm_parameters => {
        :type => "MACCS",
        :min_sim => 0.7,
      }
    }
    model = Model::LazarRegression.create dataset, params
    cv = RegressionCrossValidation.create model
    cv.validation_ids.each do |vid|
      model = Model::Lazar.find(Validation.find(vid).model_id)
      assert_equal params[:neighbor_algorithm_parameters][:type], model[:neighbor_algorithm_parameters][:type]
      assert_equal params[:neighbor_algorithm_parameters][:min_sim], model[:neighbor_algorithm_parameters][:min_sim]
      refute_equal params[:neighbor_algorithm_parameters][:training_dataset_id], model[:neighbor_algorithm_parameters][:training_dataset_id]
    end

    refute_nil cv.rmse
    refute_nil cv.mae 
  end

  def test_physchem_regression_crossvalidation

    training_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi.csv")
    model = Model::LazarRegression.create(training_dataset, :prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression")
    cv = RegressionCrossValidation.create model
    refute_nil cv.rmse
    refute_nil cv.mae 
  end

  # LOO

  def test_classification_loo_validation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::LazarClassification.create dataset
    loo = ClassificationLeaveOneOutValidation.create model
    assert_equal 14, loo.nr_unpredicted
    refute_empty loo.confusion_matrix
    assert loo.accuracy > 0.77
  end

  def test_regression_loo_validation
    dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi.csv")
    model = Model::LazarRegression.create dataset
    loo = RegressionLeaveOneOutValidation.create model
    assert loo.r_squared > 0.34
  end

  # repeated CV

  def test_repeated_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::LazarClassification.create dataset
    repeated_cv = RepeatedCrossValidation.create model
    repeated_cv.crossvalidations.each do |cv|
      assert_operator cv.accuracy, :>, 0.7, "model accuracy < 0.7, this may happen by chance due to an unfavorable training/test set split"
    end
  end

end
