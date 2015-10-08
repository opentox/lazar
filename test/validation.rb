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
    File.open("tmp.svg","w+"){|f| f.puts cv.confidence_plot}
    `inkview tmp.svg`
    p cv.nr_unpredicted
    p cv.accuracy
    #assert cv.weighted_accuracy > cv.accuracy, "Weighted accuracy should be larger than unweighted accuracy."
  end

  def test_default_regression_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    model = Model::LazarRegression.create dataset
    cv = RegressionCrossValidation.create model
    #cv = RegressionCrossValidation.find '561503262b72ed54fd000001'
    p cv.id
    File.open("tmp.svg","w+"){|f| f.puts cv.correlation_plot}
    `inkview tmp.svg`
    File.open("tmp.svg","w+"){|f| f.puts cv.confidence_plot}
    `inkview tmp.svg`
    
    #puts cv.misclassifications.to_yaml
    p cv.rmse
    p cv.weighted_rmse 
    assert cv.rmse < 1.5, "RMSE > 1.5"
    #assert cv.weighted_rmse < cv.rmse, "Weighted RMSE (#{cv.weighted_rmse}) larger than unweighted RMSE(#{cv.rmse}) "
    p cv.mae 
    p cv.weighted_mae 
    assert cv.mae < 1
    #assert cv.weighted_mae < cv.mae
  end

  def test_regression_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.medi.csv"
    #dataset = Dataset.from_csv_file "#{DATA_DIR}/EPAFHM.csv"
    params = {
      :prediction_algorithm => "OpenTox::Algorithm::Regression.weighted_average",
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

    assert cv.rmse < 1.5, "RMSE > 30"
    assert cv.mae < 1
  end

  def test_repeated_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::LazarClassification.create dataset
    repeated_cv = RepeatedCrossValidation.create model
    repeated_cv.crossvalidations.each do |cv|
      assert_operator cv.accuracy, :>, 0.7, "model accuracy < 0.7, this may happen by chance due to an unfavorable training/test set split"
      assert_operator cv.weighted_accuracy, :>, cv.accuracy
    end
  end

  def test_crossvalidation_parameters
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    params = {
      :neighbor_algorithm_parameters => {
        :min_sim => 0.3,
        :type => "FP3"
      }
    }
    model = Model::LazarClassification.create dataset, params
    model.save
    cv = ClassificationCrossValidation.create model
    params = model.neighbor_algorithm_parameters
    params = Hash[params.map{ |k, v| [k.to_s, v] }] # convert symbols to string
    cv.validations.each do |validation|
      assert_equal params, validation.model.neighbor_algorithm_parameters
    end
  end

  def test_physchem_regression_crossvalidation
    skip

    @descriptors = OpenTox::Algorithm::Descriptor::OBDESCRIPTORS.keys
    refute_empty @descriptors

    # UPLOAD DATA
    training_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi.csv")
    feature_dataset = Algorithm::Descriptor.physchem training_dataset, @descriptors
    feature_dataset.save
    scaled_feature_dataset = feature_dataset.scale
    scaled_feature_dataset.save
    model = Model::LazarRegression.create training_dataset
    model.neighbor_algorithm = "physchem_neighbors"
    model.neighbor_algorithm_parameters = {
      :feature_calculation_algorithm => "OpenTox::Algorithm::Descriptor.physchem",
      :descriptors => @descriptors,
      :feature_dataset_id => scaled_feature_dataset.id,
      :min_sim => 0.3
    }
    model.save
    cv = RegressionCrossValidation.create model
    p cv
  end

end
