require_relative "setup.rb"

class ValidationRegressionTest < MiniTest::Test
  include OpenTox::Validation

  # defaults
  
  def test_default_regression_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi_log10.csv"
    model = Model::Lazar.create training_dataset: dataset
    cv = RegressionCrossValidation.create model
    assert cv.rmse < 1.5, "RMSE #{cv.rmse} should be smaller than 1.5, this may occur due to an unfavorable training/test set split"
    assert cv.mae < 1, "MAE #{cv.mae} should be smaller than 1, this may occur due to an unfavorable training/test set split"
  end

  # parameters
  
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
    training_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create training_dataset:training_dataset
    cv = RegressionCrossValidation.create model
    refute_nil cv.rmse
    refute_nil cv.mae 
  end

  # LOO

  def test_regression_loo_validation
    dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create training_dataset: dataset
    loo = RegressionLeaveOneOut.create model
    assert loo.r_squared > 0.34, "R^2 (#{loo.r_squared}) should be larger than 0.034"
  end

end
