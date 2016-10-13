require_relative "setup.rb"

class NanoparticleTest  < MiniTest::Test
  include OpenTox::Validation

  def setup
    @training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
    unless @training_dataset
      Import::Enanomapper.import File.join(File.dirname(__FILE__),"data","enm")
      @training_dataset = Dataset.where(name: "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
    end
    @prediction_feature = @training_dataset.features.select{|f| f["name"] == 'log2(Net cell association)'}.first
  end

  def test_nanoparticle_model
    model = Model::Lazar.create training_dataset: @training_dataset, prediction_feature: @prediction_feature
    nanoparticle = @training_dataset.nanoparticles[-34]
    prediction = model.predict nanoparticle
    refute_nil prediction[:value]
    assert_includes nanoparticle.dataset_ids, @training_dataset.id
    assert true, @prediction_feature.measured
    model.delete
  end

  # validations

  def test_validate_default_nanoparticle_model
    model = Model::Lazar.create training_dataset: @training_dataset, prediction_feature: @prediction_feature
    cv = CrossValidation.create model
    p cv.rmse
    p cv.r_squared
    #File.open("tmp.pdf","w+"){|f| f.puts cv.correlation_plot}
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_pls_nanoparticle_model
    algorithms = {
      :descriptors => { :types => ["P-CHEM"] },
      :prediction => {:parameters => 'pls' },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    assert_equal "pls", model.algorithms[:prediction][:parameters]
    assert_equal "Algorithm::Caret.regression", model.algorithms[:prediction][:method]
    cv = CrossValidation.create model
    p cv.rmse
    p cv.r_squared
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_proteomics_pls_nanoparticle_model
    algorithms = {
      :descriptors => { :types => ["Proteomics"] },
      :prediction => { :parameters => 'pls' }
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    assert_equal "pls", model.algorithms[:prediction][:parameters]
    assert_equal "Algorithm::Caret.regression", model.algorithms[:prediction][:method]
    cv = CrossValidation.create model
    p cv.rmse
    p cv.r_squared
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_all_default_nanoparticle_model
    algorithms = {
      :descriptors => {
        :types => ["Proteomics","P-CHEM"]
      },
    }
    model = Model::Lazar.create prediction_feature: @prediction_feature, training_dataset: @training_dataset, algorithms: algorithms
    cv = CrossValidation.create model
    p cv.rmse
    p cv.r_squared
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end


  def test_import_ld
    skip # Ambit JSON-LD export defunct
    dataset_ids = Import::Enanomapper.import_ld
  end
end
