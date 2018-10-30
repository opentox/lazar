require_relative "setup.rb"

class ValidationClassificationTest < MiniTest::Test
  include OpenTox::Validation

  # defaults

  def test_default_classification_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::Lazar.create training_dataset: dataset
    cv = ClassificationCrossValidation.create model
    assert cv.accuracy[:without_warnings] > 0.65, "Accuracy (#{cv.accuracy[:without_warnings]}) should be larger than 0.65, this may occur due to an unfavorable training/test set split"
    assert cv.weighted_accuracy[:all] > cv.accuracy[:all], "Weighted accuracy (#{cv.weighted_accuracy[:all]}) should be larger than accuracy (#{cv.accuracy[:all]})."
    File.open("/tmp/tmp.pdf","w+"){|f| f.puts cv.probability_plot(format:"pdf")}
    assert_match "PDF", `file -b /tmp/tmp.pdf`
    File.open("/tmp/tmp.png","w+"){|f| f.puts cv.probability_plot(format:"png")}
    assert_match "PNG", `file -b /tmp/tmp.png`
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
    params = JSON.parse(params.to_json) # convert symbols to string
    
    cv.validations.each do |validation|
      validation_params = validation.model.algorithms
      refute_nil model.training_dataset_id
      refute_nil validation.model.training_dataset_id
      refute_equal model.training_dataset_id, validation.model.training_dataset_id
      assert_equal params, validation_params
    end
  end
  
  # LOO

  def test_classification_loo_validation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::Lazar.create training_dataset: dataset
    loo = ClassificationLeaveOneOut.create model
    assert_equal 77, loo.nr_unpredicted
    refute_empty loo.confusion_matrix
    assert loo.accuracy[:without_warnings] > 0.650
    assert loo.weighted_accuracy[:all] > loo.accuracy[:all], "Weighted accuracy (#{loo.weighted_accuracy[:all]}) should be larger than accuracy (#{loo.accuracy[:all]})."
  end

  # repeated CV

  def test_repeated_crossvalidation
    dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    model = Model::Lazar.create training_dataset: dataset
    repeated_cv = RepeatedCrossValidation.create model
    repeated_cv.crossvalidations.each do |cv|
      assert_operator cv.accuracy[:without_warnings], :>, 0.65, "model accuracy < 0.65, this may happen by chance due to an unfavorable training/test set split"
    end
  end
  
  def test_validation_model
    m = Model::Validation.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    [:endpoint,:species,:source].each do |p|
      refute_empty m[p]
    end
    puts m.to_json
    assert m.classification?
    refute m.regression?
    m.crossvalidations.each do |cv|
      assert cv.accuracy[:without_warnings] > 0.65, "Crossvalidation accuracy (#{cv.accuracy[:without_warnings]}) should be larger than 0.65. This may happen due to an unfavorable training/test set split."
    end
    prediction = m.predict Compound.from_smiles("OCC(CN(CC(O)C)N=O)O")
    assert_equal "false", prediction[:value]
    m.delete
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
