require_relative "setup.rb"
class DescriptorLongTest < MiniTest::Test

  def test_dataset_all
    dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.mini.csv")
    d = OpenTox::Algorithm::Descriptor.physchem dataset
    assert_equal dataset.compounds, d.compounds
    assert_equal 332, d.features.size
    assert_equal 332, d.data_entries.first.size
    d.delete
  end

end
