require_relative "setup.rb"

class DownloadTest < MiniTest::Test

  def test_pubchem_classification
    Download.pubchem_classification aid: 1191, active: "carcinogen", inactive: "non-carcinogen", species: "Hamster", endpoint: "Carcinogen"
    csv = File.join(File.dirname(__FILE__),"..","data","Carcinogen-Hamster.csv")
    meta_file = File.join(File.dirname(__FILE__),"..","data","Carcinogen-Hamster.json")
    assert File.exists?(csv)
    table = CSV.read csv
    assert_equal 87, table.size
    assert_equal ["48413129", "CC=O", "carcinogen"], table[1]
    meta = JSON.parse(File.read(meta_file))
    assert_equal "Hamster", meta["species"]
    assert_equal 1, meta["warnings"].size
    FileUtils.rm(csv)
    FileUtils.rm(meta_file)
  end

end


