require_relative "setup.rb"

class ValidationTest < MiniTest::Test
  include OpenTox::Validation

  # defaults
  
  def test_default_classification_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::Lazar.create training_dataset: dataset
    cv = ClassificationCrossValidation.create model
    assert cv.accuracy > 0.7, "Accuracy (#{cv.accuracy}) should be larger than 0.7, this may occur due to an unfavorable training/test set split"
    assert cv.weighted_accuracy > cv.accuracy, "Weighted accuracy (#{cv.weighted_accuracy}) should be larger than accuracy (#{cv.accuracy})."
  end

  def test_default_regression_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    model = Model::Lazar.create training_dataset: dataset
    cv = RegressionCrossValidation.create model
    assert cv.rmse < 1.5, "RMSE #{cv.rmse} should be smaller than 1.5, this may occur due to an unfavorable training/test set split"
    assert cv.mae < 1, "MAE #{cv.mae} should be smaller than 1, this may occur due to an unfavorable training/test set split"
  end

  # parameters

  def test_classification_crossvalidation_parameters
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    algorithms = {
      :similarity => { :min => 0.3, },
      :descriptors => { :type => "FP3" }
    }
    model = Model::Lazar.create training_dataset: dataset, algorithms: algorithms
    cv = ClassificationCrossValidation.create model
    params = model.algorithms
    params = Hash[params.map{ |k, v| [k.to_s, v] }] # convert symbols to string
    
    cv.validations.each do |validation|
      validation_params = validation.model.algorithms
      refute_nil model.training_dataset_id
      refute_nil validation.model.training_dataset_id
      refute_equal model.training_dataset_id, validation.model.training_dataset_id
      ["min_sim","type","prediction_feature_id"].each do |k|
        assert_equal params[k], validation_params[k]
      end
    end
  end
  
  def test_regression_crossvalidation_params
    dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    algorithms = {
      :prediction => { :method => "OpenTox::Algorithm::Regression.weighted_average" },
      :descriptors => { :type => "MACCS", },
      :similarity => {:min => 0.7}
    }
    model = Model::Lazar.create training_dataset: dataset, algorithms: algorithms
    assert_equal algorithms[:descriptors][:type], model.algorithms[:descriptors][:type]
    cv = RegressionCrossValidation.create model
    cv.validation_ids.each do |vid|
      model = Model::Lazar.find(Validation.find(vid).model_id)
      assert_equal algorithms[:descriptors][:type], model.algorithms[:descriptors][:type]
      assert_equal algorithms[:similarity][:min], model.algorithms[:similarity][:min]
      refute_nil model.training_dataset_id
      refute_equal dataset.id, model.training_dataset_id
    end

    refute_nil cv.rmse
    refute_nil cv.mae 
  end

  def test_physchem_regression_crossvalidation
    skip # TODO: fix
    training_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create(training_dataset.features.first, training_dataset, :prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression")
    cv = RegressionCrossValidation.create model
    refute_nil cv.rmse
    refute_nil cv.mae 
  end

  # LOO

  def test_classification_loo_validation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::Lazar.create training_dataset: dataset
    loo = ClassificationLeaveOneOut.create model
    assert_equal 14, loo.nr_unpredicted
    refute_empty loo.confusion_matrix
    assert loo.accuracy > 0.77
    assert loo.weighted_accuracy > loo.accuracy, "Weighted accuracy (#{loo.weighted_accuracy}) should be larger than accuracy (#{loo.accuracy})."
  end

  def test_regression_loo_validation
    dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create training_dataset: dataset
    loo = RegressionLeaveOneOut.create model
    assert loo.r_squared > 0.34, "R^2 (#{loo.r_squared}) should be larger than 0.034"
  end

  # repeated CV

  def test_repeated_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::Lazar.create training_dataset: dataset
    repeated_cv = RepeatedCrossValidation.create model
    repeated_cv.crossvalidations.each do |cv|
      assert_operator cv.accuracy, :>, 0.7, "model accuracy < 0.7, this may happen by chance due to an unfavorable training/test set split"
    end
  end

end
