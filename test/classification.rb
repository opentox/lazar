require_relative "setup.rb"

class LazarClassificationTest < MiniTest::Test

  def test_lazar_classification
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::LazarClassification.create training_dataset

    [ {
      :compound => OpenTox::Compound.from_inchi("InChI=1S/C6H6/c1-2-4-6-5-3-1/h1-6H"),
      :prediction => "false",
      :confidence => 0.25281385281385277,
      :nr_neighbors => 11
    },{
      :compound => OpenTox::Compound.from_smiles("c1ccccc1NN"),
      :prediction => "false",
      :confidence => 0.3639589577089577,
      :nr_neighbors => 14
    } ].each do |example|
      prediction = model.predict example[:compound]
      assert_equal example[:prediction], prediction[:value]
      #assert_equal example[:confidence], prediction[:confidence]
      #assert_equal example[:nr_neighbors], prediction[:neighbors].size
    end

    compound = Compound.from_smiles "CCO"
    prediction = model.predict compound
    assert_equal ["false"], prediction[:database_activities]
    assert_equal "true", prediction[:value]

    # make a dataset prediction
    compound_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.mini.csv")
    prediction = model.predict compound_dataset
    assert_equal compound_dataset.compounds, prediction.compounds

    cid = prediction.compounds[7].id.to_s
    assert_equal "Could not find similar compounds with experimental data in the training dataset.", prediction.predictions[cid][:warning]
    cid = prediction.compounds[9].id.to_s
    assert_equal "1 compounds have been removed from neighbors, because they have the same structure as the query compound.", prediction.predictions[cid][:warning]
    # cleanup
    [training_dataset,model,compound_dataset].each{|o| o.delete}
  end
end
