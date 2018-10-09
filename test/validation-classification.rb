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

  def test_carcinogenicity_rf_classification
    skip "Caret rf classification may run into a (endless?) loop for some compounds."
    dataset = Dataset.from_csv_file "#{DATA_DIR}/multi_cell_call.csv"
    algorithms = {
      :prediction => {
        :method => "Algorithm::Caret.rf",
      },
    }
    model = Model::Lazar.create training_dataset: dataset, algorithms: algorithms
    cv = ClassificationCrossValidation.create model
#    cv = ClassificationCrossValidation.find "5bbc822dca626919731e2822"
    puts cv.statistics
    puts cv.id
    
  end

  def test_mutagenicity_classification_algorithms
    skip "Caret rf classification may run into a (endless?) loop for some compounds."
    source_feature = Feature.where(:name => "Ames test categorisation").first
    target_feature = Feature.where(:name => "Mutagenicity").first
    kazius = Dataset.from_sdf_file "#{DATA_DIR}/cas_4337.sdf"
    hansen = Dataset.from_csv_file "#{DATA_DIR}/hansen.csv"
    efsa = Dataset.from_csv_file "#{DATA_DIR}/efsa.csv"
    dataset = Dataset.merge [kazius,hansen,efsa], {source_feature => target_feature}, {1 => "mutagen", 0 => "nonmutagen"}
    model = Model::Lazar.create training_dataset: dataset
    repeated_cv = RepeatedCrossValidation.create model
    puts repeated_cv.id
    repeated_cv.crossvalidations.each do |cv|
      puts cv.accuracy
      puts cv.confusion_matrix
    end
    algorithms = {
      :prediction => {
        :method => "Algorithm::Caret.rf",
      },
    }
    model = Model::Lazar.create training_dataset: dataset, algorithms: algorithms
    repeated_cv = RepeatedCrossValidation.create model
    puts repeated_cv.id
    repeated_cv.crossvalidations.each do |cv|
      puts cv.accuracy
      puts cv.confusion_matrix
    end
    
  end

end
