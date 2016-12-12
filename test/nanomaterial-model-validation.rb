require_relative "setup.rb"

class NanomaterialValidationModelTest < MiniTest::Test

  def setup
    @training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
    @prediction_feature = @training_dataset.features.select{|f| f["name"] == 'log2(Net cell association)'}.first
  end

  def test_default_nanomaterial_validation_model
    validation_model = Model::NanoValidation.create
    [:endpoint,:species,:source].each do |p|
      refute_empty validation_model[p]
    end
    assert validation_model.regression?
    refute validation_model.classification?
    validation_model.crossvalidations.each do |cv|
      refute_nil cv.r_squared
      refute_nil cv.rmse
    end
    nanoparticle = @training_dataset.nanoparticles[-34]
    assert_includes nanoparticle.dataset_ids, @training_dataset.id
    prediction = validation_model.predict nanoparticle
    refute_nil prediction[:value]
    assert_includes prediction[:prediction_interval][0]..prediction[:prediction_interval][1], prediction[:measurements].median, "This assertion assures that measured values are within the prediction interval. It may fail in 5% of the predictions."
    validation_model.delete
  end

  def test_nanomaterial_validation_model_parameters
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
    validation_model = Model::NanoValidation.create algorithms: algorithms
    assert validation_model.regression?
    refute validation_model.classification?
    validation_model.crossvalidations.each do |cv|
      refute_nil cv.r_squared
      refute_nil cv.rmse
    end
    nanoparticle = @training_dataset.nanoparticles[-34]
    assert_includes nanoparticle.dataset_ids, @training_dataset.id
    prediction = validation_model.predict nanoparticle
    refute_nil prediction[:value]
    assert_includes prediction[:prediction_interval][0]..prediction[:prediction_interval][1], prediction[:measurements].median, "This assertion assures that measured values are within the prediction interval. It may fail in 5% of the predictions."
  end
end
