require_relative "setup.rb"

class NanoparticleModelTest  < MiniTest::Test
  include OpenTox::Validation

  def setup
    @training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
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

  def test_nanoparticle_fingerprint_model
    assert true, @prediction_feature.measured
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
    model = Model::Lazar.create training_dataset: @training_dataset, prediction_feature: @prediction_feature, algorithms: algorithms
    refute_empty model.dependent_variables
    refute_empty model.descriptor_ids
    refute_empty model.independent_variables
    assert_equal "Algorithm::Caret.rf", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.tanimoto", model.algorithms[:similarity][:method]
    assert_nil model.algorithms[:descriptors][:categories]
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

  def test_nanoparticle_fingerprint_model_with_feature_selection
    assert true, @prediction_feature.measured
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D",
      },
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => 0.1
      },
    }
    model = Model::Lazar.create training_dataset: @training_dataset, prediction_feature: @prediction_feature, algorithms: algorithms
    refute_empty model.algorithms[:feature_selection]
    refute_empty model.dependent_variables
    refute_empty model.descriptor_ids
    refute_empty model.independent_variables
    assert_equal "Algorithm::Caret.rf", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.tanimoto", model.algorithms[:similarity][:method]
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

  def test_nanoparticle_calculated_properties_model
    skip "Nanoparticle calculate_properties similarity not yet implemented"
    assert true, @prediction_feature.measured
    algorithms = {
      :descriptors => {
        :method => "calculate_properties",
        :features => PhysChem.openbabel_descriptors,
      },
      :similarity => {
        :method => "Algorithm::Similarity.weighted_cosine",
        :min => 0.5
      },
      :prediction => {
        :method => "Algorithm::Regression.weighted_average",
      },
    }
    model = Model::Lazar.create training_dataset: @training_dataset, prediction_feature: @prediction_feature, algorithms: algorithms
    refute_empty model.dependent_variables
    refute_empty model.descriptor_ids
    refute_empty model.independent_variables
    assert_equal "Algorithm::Caret.rf", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.weighted", model.algorithms[:similarity][:method]
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

  def test_import_ld
    skip # Ambit JSON-LD export defunct
    dataset_ids = Import::Enanomapper.import_ld
  end
end
