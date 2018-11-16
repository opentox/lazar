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

  def test_import_daphnia
    Download.daphnia
    table = CSV.read File.join(Download::DATA,"Acute_toxicity-Daphnia_magna.csv")
    assert_equal "BrC(Br)Br", table[1][1]
    assert_equal 0.74, table[1][2].to_f.round(2)
    assert_equal "-log[LC50_mmol/L]", table[0][2]
  end

end


