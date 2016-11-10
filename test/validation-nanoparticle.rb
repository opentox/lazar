require_relative "setup.rb"

class NanoparticleValidationTest  < MiniTest::Test
  include OpenTox::Validation

  def setup
    @training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
    unless @training_dataset
      Import::Enanomapper.import File.join(File.dirname(__FILE__),"data","enm")
      @training_dataset = Dataset.where(name: "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
    end
    @prediction_feature = @training_dataset.features.select{|f| f["name"] == 'log2(Net cell association)'}.first
  end

  def test_validate_default_nanoparticle_model
    model = Model::Lazar.create training_dataset: @training_dataset, prediction_feature: @prediction_feature
    cv = CrossValidation.create model
    p cv
    p cv.rmse
    p cv.r_squared
    #File.open("tmp.pdf","w+"){|f| f.puts cv.correlation_plot}
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_pls_nanoparticle_model
    algorithms = {
      :descriptors => {
        :method => "properties",
        :categories => ["P-CHEM"]
      },
      :prediction => {:method => 'Algorithm::Caret.pls' },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    assert_equal "Algorithm::Caret.pls", model.algorithms[:prediction][:method]
    cv = CrossValidation.create model
    p cv.rmse
    p cv.r_squared
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_proteomics_pls_nanoparticle_model
    algorithms = {
      :descriptors => {
        :method => "properties",
        :categories => ["Proteomics"]
      },
      :prediction => {:method => 'Algorithm::Caret.pls' },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    assert_equal "Algorithm::Caret.pls", model.algorithms[:prediction][:method]
    cv = CrossValidation.create model
    p cv.rmse
    p cv.r_squared
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_all_default_nanoparticle_model
    algorithms = {
      :descriptors => {
        :method => "properties",
        :categories => ["Proteomics","P-CHEM"]
      },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    cv = CrossValidation.create model
    p cv.rmse
    p cv.r_squared
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

end
