require_relative "setup.rb"

class UseCasesTest < MiniTest::Test

  def test_PA
    # TODO add assertions
    skip "This test ist very time consuming, enable on demand."
    kazius = Dataset.from_sdf_file "#{DATA_DIR}/cas_4337.sdf"
    hansen = Dataset.from_csv_file "#{DATA_DIR}/hansen.csv"
    efsa = Dataset.from_csv_file "#{DATA_DIR}/efsa.csv"
    datasets = [kazius,hansen,efsa]
    map = {"1" => "mutagen", "0" => "nonmutagen"}
    #p "merging"
    training_dataset = Dataset.merge datasets: datasets, features: datasets.collect{|d| d.bioactivity_features.first}, value_maps: [nil,map,map], keep_original_features: false, remove_duplicates: true
    assert_equal 8281, training_dataset.compounds.size
    #p training_dataset.features.size
    #p training_dataset.id
    #training_dataset = Dataset.find('5bd8ac8fca62695d767fca6b')
    #training_dataset = Dataset.find('5bd8bbadca62695f69e7a33b')
    #puts training_dataset.to_csv
    #p "create model_validation"
    model_validation = Model::Validation.from_dataset training_dataset: training_dataset, prediction_feature: training_dataset.merged_features.first, species: "Salmonella typhimurium", endpoint: "Mutagenicity"
    #p model_validation.id
    #model_validation = Model::Validation.find '5bd8df47ca6269604590ab38'
    #p model_validation.crossvalidations.first.predictions.select{|cid,p| !p["warnings"].empty?}
    #p "predict"
    pa = Dataset.from_sdf_file "#{DATA_DIR}/PA.sdf"
    prediction_dataset = model_validation.predict pa
    #p prediction_dataset.id
    #prediction_dataset = Dataset.find('5bd98b88ca6269609aab79f4')
    #puts prediction_dataset.to_csv
  end

  def test_tox21
    # TODO add assertions
    skip "This test ist very time consuming, enable on demand."
    training_dataset = Dataset.from_pubchem_aid 743122
    #p training_dataset.id
    #'5bd9a1dbca626969d97fb421'
    #File.open("AID743122.csv","w+"){|f| f.puts training_dataset.to_csv}
    #model = Model::Lazar.create training_dataset: training_dataset
    #p model.id
    #p Model::Lazar.find('5bd9a70bca626969d97fc9df')
    model_validation = Model::Validation.from_dataset training_dataset: training_dataset, prediction_feature: training_dataset.bioactivity_features.first, species: "Human HG2L7.5c1 cell line", endpoint: "aryl hydrocarbon receptor (AhR) signaling pathway activation"
    #model_validation = Model::Validation.find '5bd9b210ca62696be39ab74d'
    #model_validation.crossvalidations.each do |cv|
      #p cv
    #end
    #p model_validation.crossvalidations.first.predictions.select{|cid,p| !p["warnings"].empty?}
  end

  def test_download_public_models
    Download.public_data
  end

  def test_import_public_models
    skip
    Import.public_data
  end

end
