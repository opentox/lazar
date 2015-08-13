require_relative "setup.rb"
class DescriptorLongTest < MiniTest::Test

  def test_dataset_all
    # TODO: improve CDK descriptor calculation speed or add timeout
    skip "CDK descriptor calculation takes too long for some compounds"
    dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.mini.csv")
    d = OpenTox::Algorithm::Descriptor.physchem dataset
    assert_equal dataset.compounds, d.compounds
    assert_equal 332, d.features.size
    assert_equal 332, d.data_entries.first.size
    d.delete
  end

  def test_dataset_openbabel
    # TODO: improve CDK descriptor calculation speed or add timeout
    dataset = Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.mini.csv")
    d = Algorithm::Descriptor.physchem dataset, Algorithm::Descriptor::OBDESCRIPTORS.keys
    assert_equal dataset.compounds, d.compounds
    size = Algorithm::Descriptor::OBDESCRIPTORS.keys.size
    assert_equal size, d.features.size
    assert_equal size, d.data_entries.first.size
    d.delete
  end

end
