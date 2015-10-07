require_relative "setup.rb"

class LazarPhyschemDescriptorTest < MiniTest::Test
  def test_epafhm

    skip
    @descriptors = OpenTox::Algorithm::Descriptor::OBDESCRIPTORS.keys
    refute_empty @descriptors

    # UPLOAD DATA
    training_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi.csv")
    feature_dataset = Algorithm::Descriptor.physchem training_dataset, @descriptors
    scaled_feature_dataset = feature_dataset.scale
    model = Model::LazarRegression.create training_dataset
    model.neighbor_algorithm = "physchem_neighbors"
    model.neighbor_algorithm_parameters = {
      :feature_calculation_algorithm => "OpenTox::Algorithm::Descriptor.physchem",
      :descriptors => @descriptors,
      :feature_dataset_id => scaled_feature_dataset.id,
      :min_sim => 0.3
    }
    model.save
    compound = Compound.from_smiles "CC(C)(C)CN"
    prediction = model.predict compound
    refute_nil prediction[:value]
    refute_nil prediction[:confidence]
    prediction[:neighbors].each do |line|
      assert_operator line[1], :>, 0.3
    end
  end
end
