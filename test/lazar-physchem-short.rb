require_relative "setup.rb"

class LazarPhyschemDescriptorTest < MiniTest::Test
  def test_epafhm
    skip "Physchem Regression not yet implemented."
    # check available descriptors
    @descriptors = OpenTox::Algorithm::Descriptor::DESCRIPTORS.keys
    assert_equal 111,@descriptors.size,"wrong number of physchem descriptors"
    @descriptor_values = OpenTox::Algorithm::Descriptor::DESCRIPTOR_VALUES

    # select descriptors for test
    @num_features_offset = 0
    @descriptors.keep_if{|x| x=~/^Openbabel\./}
    @descriptors.delete("Openbabel.L5") # TODO Openbabel.L5 does not work, investigate!!!
    puts "Descriptors: #{@descriptors}"

    # UPLOAD DATA
    training_dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"EPAFHM.medi.csv")
    puts "Dataset: "+training_dataset.id
#    feature_dataset = Algorithm::Descriptor.physchem training_dataset, @descriptors
    model = Model::LazarRegression.create training_dataset#, feature_dataset
    #p model
    compound = Compound.from_smiles "CC(C)(C)CN"
    prediction = model.predict compound
    p prediction

  end
end
