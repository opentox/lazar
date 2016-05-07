require_relative "setup.rb"

class LazarClassificationTest < MiniTest::Test

  def test_lazar_classification
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::LazarClassification.create training_dataset.features.first, training_dataset

    [ {
      :compound => OpenTox::Compound.from_inchi("InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"),
      :prediction => "false",
    },{
      :compound => OpenTox::Compound.from_smiles("c1ccccc1NN"),
      :prediction => "false",
    } ].each do |example|
      prediction = model.predict example[:compound]
      assert_equal example[:prediction], prediction[:value]
    end

    compound = Compound.from_smiles "CCO"
    prediction = model.predict compound
    assert_equal "true", prediction[:value]
    assert_equal ["false"], prediction[:database_activities]

    # make a dataset prediction
    compound_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.mini_log10.csv")
    prediction_dataset = model.predict compound_dataset
    assert_equal compound_dataset.compounds, prediction_dataset.compounds

    cid = prediction_dataset.compounds[7].id.to_s
    assert_equal "Could not find similar compounds with experimental data in the training dataset.", prediction_dataset.predictions[cid][:warning]
    prediction_dataset.predictions.each do |cid,pred|
      assert_equal "Could not find similar compounds with experimental data in the training dataset.", pred[:warning] if pred[:value].nil?
    end
    cid = Compound.from_smiles("CCOC(=O)N").id.to_s
    assert_equal "1 compounds have been removed from neighbors, because they have the same structure as the query compound.", prediction_dataset.predictions[cid][:warning]
    # cleanup
    [training_dataset,model,compound_dataset,prediction_dataset].each{|o| o.delete}
  end

  def test_lazar_kazius
    t = Time.now
    dataset = Dataset.from_csv_file File.join(DATA_DIR,"kazius.csv")
    t = Time.now
    model = Model::LazarClassification.create(dataset.features.first,dataset)
    t = Time.now
    2.times do
      compound = Compound.from_smiles("Clc1ccccc1NN")
      prediction = model.predict compound
      assert_equal "1", prediction[:value]
      #assert_in_delta 0.019858401199860445, prediction[:confidence], 0.001
    end
    dataset.delete
  end
end
