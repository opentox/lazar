require_relative "setup.rb"

class NanoparticleValidationTest  < MiniTest::Test
  include OpenTox::Validation

  def setup
    @training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
    @prediction_feature = @training_dataset.features.select{|f| f["name"] == 'log2(Net cell association)'}.first
  end

  def test_validate_default_nanoparticle_model
    model = Model::Lazar.create training_dataset: @training_dataset, prediction_feature: @prediction_feature
    cv = CrossValidation.create model
    p cv.id
    File.open("tmp.pdf","w+"){|f| f.puts cv.correlation_plot format:"pdf"}
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_pls_pchem_model
    algorithms = {
      :descriptors => {
        :method => "properties",
        :categories => ["P-CHEM"]
      },
      :prediction => {:method => 'Algorithm::Caret.pls' },
      :feature_selection => {
        :method => "Algorithm::FeatureSelection.correlation_filter",
      },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    assert_equal "Algorithm::Caret.pls", model.algorithms[:prediction][:method]
    cv = CrossValidation.create model
    p cv.id
    File.open("tmp2.pdf","w+"){|f| f.puts cv.correlation_plot format:"pdf"}
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

=begin
  def test_validate_proteomics_pls_pchem_model
    algorithms = {
      :descriptors => {
        :method => "properties",
        :categories => ["Proteomics"]
      },
      :prediction => {:method => 'Algorithm::Caret.pls' },
      :feature_selection => {
        :method => "Algorithm::FeatureSelection.correlation_filter",
      },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    assert_equal "Algorithm::Caret.pls", model.algorithms[:prediction][:method]
    cv = CrossValidation.create model
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end
=end

  def test_validate_proteomics_pchem_default_model
    algorithms = {
      :descriptors => {
        :method => "properties",
        :categories => ["Proteomics","P-CHEM"]
      },
      :feature_selection => {
        :method => "Algorithm::FeatureSelection.correlation_filter",
      },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    cv = CrossValidation.create model
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_nanoparticle_fingerprint_model_without_feature_selection
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D",
      },
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => 0.1
      },
      :feature_selection => nil
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    cv = CrossValidation.create model
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_nanoparticle_fingerprint_weighted_average_model_without_feature_selection
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D",
      },
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => 0.1
      },
      :prediction => { :method => "OpenTox::Algorithm::Regression.weighted_average" },
      :feature_selection => nil
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    cv = CrossValidation.create model
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_nanoparticle_fingerprint_model_with_feature_selection
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D",
      },
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => 0.1
      },
      :feature_selection => {
        :method => "Algorithm::FeatureSelection.correlation_filter",
      },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    cv = CrossValidation.create model
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

end
