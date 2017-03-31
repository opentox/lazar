require_relative "setup.rb"

class ValidationClassificationTest < MiniTest::Test
  include OpenTox::Validation

  # defaults
  
  def test_default_classification_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::Lazar.create training_dataset: dataset
    cv = ClassificationCrossValidation.create model
    assert cv.accuracy > 0.7, "Accuracy (#{cv.accuracy}) should be larger than 0.7, this may occur due to an unfavorable training/test set split"
    assert cv.weighted_accuracy > cv.accuracy, "Weighted accuracy (#{cv.weighted_accuracy}) should be larger than accuracy (#{cv.accuracy})."
    File.open("/tmp/tmp.pdf","w+"){|f| f.puts cv.probability_plot(format:"pdf")}
    p `file -b /tmp/tmp.pdf`
    File.open("/tmp/tmp.png","w+"){|f| f.puts cv.probability_plot(format:"png")}
    p `file -b /tmp/tmp.png`
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
  
  # LOO

  def test_classification_loo_validation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::Lazar.create training_dataset: dataset
    loo = ClassificationLeaveOneOut.create model
    assert_equal 24, loo.nr_unpredicted
    refute_empty loo.confusion_matrix
    assert loo.accuracy > 0.77
    assert loo.weighted_accuracy > loo.accuracy, "Weighted accuracy (#{loo.weighted_accuracy}) should be larger than accuracy (#{loo.accuracy})."
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
