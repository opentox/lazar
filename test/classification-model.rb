require_relative "setup.rb"

class ClassificationModelTest < MiniTest::Test

  def test_classification_default
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MP2D"
      },
      :similarity => {
        :method => "Algorithm::Similarity.tanimoto",
        :min => 0.5
      },
      :prediction => {
        :method => "Algorithm::Classification.weighted_majority_vote",
      },
      :feature_selection => nil,
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::Lazar.create  training_dataset: training_dataset
    assert_kind_of Model::LazarClassification, model
    assert_equal algorithms, model.algorithms
    [ {
      :compound => OpenTox::Compound.from_smiles("OCC(CN(CC(O)C)N=O)O"),
      :prediction => "false",
    },{
      :compound => OpenTox::Compound.from_smiles("O=CNc1scc(n1)c1ccc(o1)[N+](=O)[O-]"),
      :prediction => "true",
    } ].each do |example|
      prediction = model.predict example[:compound]
      assert_equal example[:prediction], prediction[:value]
    end
  end

  def test_export_import
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    export = Model::Lazar.create  training_dataset: training_dataset
    File.open("tmp.csv","w+"){|f| f.puts export.to_json }
    import = Model::LazarClassification.new JSON.parse(File.read "tmp.csv")
    assert_kind_of Model::LazarClassification, import
    import.algorithms.each{|k,v| v.transform_keys!(&:to_sym) if v.is_a? Hash}
    import.algorithms.transform_keys!(&:to_sym)
    assert_equal export.algorithms, import.algorithms
    [ {
      :compound => OpenTox::Compound.from_smiles("OCC(CN(CC(O)C)N=O)O"),
      :prediction => "false",
    },{
      :compound => OpenTox::Compound.from_smiles("O=CNc1scc(n1)c1ccc(o1)[N+](=O)[O-]"),
      :prediction => "true",
    } ].each do |example|
      prediction = import.predict example[:compound]
      assert_equal example[:prediction], prediction[:value]
    end
  end
 
  def test_classification_parameters
    algorithms = {
      :descriptors => {
        :method => "fingerprint",
        :type => "MACCS"
      },
      :similarity => {
        :min => 0.4
      },
    }
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::Lazar.create training_dataset: training_dataset, algorithms: algorithms
    assert_kind_of Model::LazarClassification, model
    assert_equal "Algorithm::Classification.weighted_majority_vote", model.algorithms[:prediction][:method]
    assert_equal "Algorithm::Similarity.tanimoto", model.algorithms[:similarity][:method]
    assert_equal algorithms[:similarity][:min], model.algorithms[:similarity][:min]
    substance = training_dataset.substances[10]
    prediction = model.predict substance
    assert_equal "false", prediction[:value]
    assert_equal 4, prediction[:neighbors].size
  end

  def test_dataset_prediction
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"multi_cell_call.csv")
    test_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::Lazar.create training_dataset: training_dataset
    result = model.predict test_dataset
    assert_kind_of Dataset, result
    assert_equal 7, result.features.size
    assert_equal 85, result.compounds.size
    prediction_feature = result.prediction_features.first
    assert_equal ["yes"], result.values(result.compounds[1], prediction_feature)
    assert_equal ["no"], result.values(result.compounds[5], prediction_feature)
    assert_nil result.predictions[result.compounds.first][:value]
    assert_equal "yes", result.predictions[result.compounds[1]][:value]
    assert_equal 0.27, result.predictions[result.compounds[1]][:probabilities]["no"].round(2)
  end

  def test_carcinogenicity_rf_classification
    skip "Caret rf may run into a (endless?) loop for some compounds."
    dataset = Dataset.from_csv_file "#{DATA_DIR}/multi_cell_call.csv"
    algorithms = {
      :prediction => {
        :method => "Algorithm::Caret.rf",
      },
    }
    model = Model::Lazar.create training_dataset: dataset, algorithms: algorithms
    substance = Compound.from_smiles "[O-]S(=O)(=O)[O-].[Mn+2].O"
    prediction = model.predict substance
    p prediction
    
  end

  def test_rf_classification
    skip "Caret rf may run into a (endless?) loop for some compounds."
    algorithms = {
      :prediction => {
        :method => "Algorithm::Caret.rf",
      },
    }
    training_dataset = Dataset.from_sdf_file File.join(DATA_DIR,"cas_4337.sdf")
    model = Model::Lazar.create  training_dataset: training_dataset, algorithms: algorithms
    #p model.id.to_s
    #model = Model::Lazar.find "5bbb4c0cca626909f6c8a924"
    assert_kind_of Model::LazarClassification, model
    assert_equal algorithms[:prediction][:method], model.algorithms["prediction"]["method"]
    substance = Compound.from_smiles "Clc1ccc(cc1)C(=O)c1ccc(cc1)OC(C(=O)O)(C)C"
    prediction = model.predict substance
    assert_equal  51, prediction[:neighbors].size
    assert_equal "nonmutagen", prediction[:value]
    assert_equal 0.1, prediction[:probabilities]["mutagen"].round(1)
    assert_equal 0.9, prediction[:probabilities]["nonmutagen"].round(1)
  end

end
