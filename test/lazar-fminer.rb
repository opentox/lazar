require_relative "setup.rb"

class LazarFminerTest < MiniTest::Test

  def test_lazar_fminer
    training_dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    model = Model::LazarFminerClassification.create training_dataset#, feature_dataset
    feature_dataset = Dataset.find model.neighbor_algorithm_parameters[:feature_dataset_id]
    assert_equal training_dataset.compounds.size, feature_dataset.compounds.size
    #TODO check fminer features, see fminer.rb
    #assert_equal 54, feature_dataset.features.size
    feature_dataset.data_entries.each do |e|
      assert_equal e.size, feature_dataset.features.size
    end
    #assert_equal 'C-C-C=C', feature_dataset.features.first.smarts

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
    }, {
      :compound => Compound.from_smiles('OCCCCCCCC\C=C/CCCCCCCC'),
      :prediction => "false",
      :confidence => 0.5555555555555556,
      :nr_neighbors => 1
    }].each do |example|
      prediction = model.predict example[:compound]

      assert_equal example[:prediction], prediction[:value]
      #assert_equal example[:confidence], prediction[:confidence]
      #assert_equal example[:nr_neighbors], prediction[:neighbors].size
    end

    # make a dataset prediction
    compound_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.mini.csv")
    prediction = model.predict compound_dataset
    assert_equal compound_dataset.compounds, prediction.compounds

    assert_equal "Cound not find similar compounds.", prediction.data_entries[7][2]
    assert_equal "measured", prediction.data_entries[14][1]
    # cleanup
    [training_dataset,model,feature_dataset,compound_dataset].each{|o| o.delete}
  end
end
