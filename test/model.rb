require_relative "setup.rb"

class ModelTest < MiniTest::Test

  def test_default_regression
    algorithms = {
      :descriptors => [ "MP2D" ],
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => 0.1
      },
      :prediction => {
        :method => "Algorithm::Caret.pls",
      },
      :feature_selection => nil,
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create  training_dataset: training_dataset
    assert_kind_of Model::LazarRegression, model
    assert_equal algorithms, model.algorithms
    substance = training_dataset.substances[10]
    prediction = model.predict substance
    assert_includes prediction[:prediction_interval][0]..prediction[:prediction_interval][1], prediction[:measurements].median, "This assertion assures that measured values are within the prediction interval. It may fail in 5% of the predictions."
  end

  def test_regression_parameters
    algorithms = {
      :descriptors => [ "MP2D" ],
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => 0.3
      },
      :prediction => {
        :method => "Algorithm::Regression.weighted_average",
      },
      :feature_selection => nil,
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi_log10.csv")
    model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
    assert_kind_of Model::LazarRegression, model
    assert_equal "Algorithm::Regression.weighted_average", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.tanimoto", model.algorithms[:similarity][:method]
    assert_equal algorithms[:similarity][:min], model.algorithms[:similarity][:min]
    assert_equal algorithms[:prediction][:parameters], model.algorithms[:prediction][:parameters]
    substance = training_dataset.substances[10]
    prediction = model.predict substance
    assert_equal 0.83, prediction[:value].round(2)
  end

  def test_physchem_regression
    algorithms = {
      :descriptors => {
        :method => "calculate_properties",
        :features => PhysChem.openbabel_descriptors,
      },
      :similarity => {
        :method => "Algorithm::Similarity.cosine",
      }
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.mini_log10.csv")
    model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
    assert_kind_of Model::LazarRegression, model
    assert_equal "Algorithm::Caret.pls", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.cosine", model.algorithms[:similarity][:method]
    assert_equal 0.1, model.algorithms[:similarity][:min]
    algorithms[:descriptors].delete :features
    assert_equal algorithms[:descriptors], model.algorithms[:descriptors]
    prediction = model.predict training_dataset.substances[10]
    refute_nil prediction[:value]
    # TODO test predictin
  end

  def test_nanoparticle_default
    training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
    unless training_dataset
      Import::Enanomapper.import File.join(File.dirname(__FILE__),"data","enm")
      training_dataset = Dataset.where(name: "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
    end
    model = Model::Lazar.create  training_dataset: training_dataset
    assert_equal "Algorithm::Caret.rf", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.weighted_cosine", model.algorithms[:similarity][:method]
    prediction = model.predict training_dataset.substances[14]
    assert_includes prediction[:prediction_interval][0]..prediction[:prediction_interval][1], prediction[:measurements].median, "This assertion assures that measured values are within the prediction interval. It may fail in 5% of the predictions."

  end

  def test_nanoparticle_parameters
    skip
  end

  def test_regression_with_feature_selection
    algorithms = {
      :feature_selection => {
        :method => "Algorithm::FeatureSelection.correlation_filter",
      },
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.mini_log10.csv")
    model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
    assert_kind_of Model::LazarRegression, model
    assert_equal "Algorithm::Caret.pls", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.tanimoto", model.algorithms[:similarity][:method]
    assert_equal 0.1, model.algorithms[:similarity][:min]
    assert_equal algorithms[:feature_selection][:method], model.algorithms[:feature_selection][:method]
  end

end
