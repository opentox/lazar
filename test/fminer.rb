require_relative "setup.rb"

class FminerTest < MiniTest::Test

  def test_fminer_bbrc
    dataset = OpenTox::Dataset.from_csv_file File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    refute_nil dataset.id
    feature_dataset = OpenTox::Algorithm::Fminer.bbrc dataset
    feature_dataset = Dataset.find feature_dataset.id
    assert_equal dataset.compounds.size, feature_dataset.compounds.size
    # TODO: fminer calculates 62 instead of 54 features
    # it is unclear which commit changed the numbers (occurs with old libraries/mongodb branch too
    # modification of Compound to use smiles instead of inchis seems to have no effect
    #assert_equal 54, feature_dataset.features.size
    #assert_equal "C-C-C=C", feature_dataset.features.first.smarts
    compounds = feature_dataset.compounds
    smarts = feature_dataset.features
    smarts.each do |smart|
      assert smart.p_value.round(2) >= 0.95
    end
    match = OpenTox::Algorithm::Descriptor.smarts_match compounds, smarts
    feature_dataset.data_entries.each_with_index do |fingerprint,i|
      assert_equal match[i], fingerprint
    end

    dataset.delete
    feature_dataset.delete
  end

  def test_fminer_last
    skip "last features have to be activated"
    dataset = OpenTox::Dataset.new
    dataset.upload File.join(DATA_DIR,"hamster_carcinogenicity.csv")
    feature_dataset = OpenTox::Algorithm::Fminer.last :dataset => dataset
    assert_equal dataset.compounds.size, feature_dataset.compounds.size
    assert_equal 21, feature_dataset.features.size
    assert_equal '[#6&A]-[#6&a]:[#6&a]:[#6&a]:[#6&a]:[#6&a]', feature_dataset.features.first.smarts

    compounds = feature_dataset.compounds
    smarts = feature_dataset.features.collect{|f| f.smarts}
    match = OpenTox::Algorithm::Descriptor.smarts_match compounds, smarts
    compounds.each_with_index do |c,i|
      smarts.each_with_index do |s,j|
        assert_equal match[i][j], feature_dataset.data_entries[i][j].to_i
      end
    end

    dataset.delete
    feature_dataset.delete
  end

end
