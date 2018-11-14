require_relative "setup.rb"

class UseCasesTest < MiniTest::Test

  def test_PA
    skip "This test ist very time consuming, enable on demand."
    Download.mutagenicity
    training_dataset = Dataset.from_csv_file File.join(Download::DATA,"Mutagenicity-Salmonella_typhimurium.csv")
    assert_equal 8281, training_dataset.compounds.size
    # TODO use Model::Validation.from_csv_file
    model_validation = Model::Validation.from_csv_file File.join(Download::DATA,"Mutagenicity-Salmonella_typhimurium.csv")
    pa = Dataset.from_sdf_file "#{DATA_DIR}/PA.sdf"
    prediction_dataset = model_validation.predict pa
    # TODO add assertions
  end

  def test_tox21
    skip "This test ist very time consuming, enable on demand."
    csv_file = Download.pubchem_classification aid: 743122, species: "Human HG2L7.5c1 cell line", endpoint: "aryl hydrocarbon receptor (AhR) signaling pathway activation"
    model_validation = Model::Validation.from_csv_file csv_file
    assert_equal 5, model_validation.crossvalidations.size
  end

  def test_download_public_models
    skip "This test will overwrite public data." 
    Download.public_data
    assert_equal 11, Dir[File.join(File.dirname(__FILE__),"..","data","*csv")].size
    assert_equal 11, Dir[File.join(File.dirname(__FILE__),"..","data","*json")].size
    # TODO: check values
  end

  def test_import_public_models
    skip "This test is very time consuming, enable on demand."
    #$mongo.database.drop
    #$gridfs = $mongo.database.fs # recreate GridFS indexes
    validated_models = Import.public_data
    assert_equal Dir[File.join(File.dirname(__FILE__),"..","data/*csv")].size, validated_models.size
  end

end
