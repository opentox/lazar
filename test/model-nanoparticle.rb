require_relative "setup.rb"

class NanoparticleModelTest  < MiniTest::Test
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
    assert true, @prediction_feature.measured
    model = Model::Lazar.create training_dataset: @training_dataset, prediction_feature: @prediction_feature
    refute_empty model.dependent_variables
    refute_empty model.descriptor_ids
    refute_empty model.independent_variables
    assert_equal "Algorithm::Caret.rf", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.weighted_cosine", model.algorithms[:similarity][:method]
    nanoparticle = @training_dataset.nanoparticles[-34]
    assert_includes nanoparticle.dataset_ids, @training_dataset.id
    prediction = model.predict nanoparticle
    refute_nil prediction[:value]
    assert_includes prediction[:prediction_interval][0]..prediction[:prediction_interval][1], prediction[:measurements].median, "This assertion assures that measured values are within the prediction interval. It may fail in 5% of the predictions."
    prediction = model.predict @training_dataset.substances[14]
    refute_nil prediction[:value]
    assert_includes prediction[:prediction_interval][0]..prediction[:prediction_interval][1], prediction[:measurements].median, "This assertion assures that measured values are within the prediction interval. It may fail in 5% of the predictions."
    model.delete
  end

  def test_nanoparticle_parameters
    skip
  end

  def test_import_ld
    skip # Ambit JSON-LD export defunct
    dataset_ids = Import::Enanomapper.import_ld
  end
end
