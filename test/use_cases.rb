require_relative "setup.rb"

class UseCasesTest < MiniTest::Test

  def test_PA
    kazius = Dataset.from_sdf_file "#{DATA_DIR}/cas_4337.sdf"
    hansen = Dataset.from_csv_file "#{DATA_DIR}/hansen.csv"
    efsa = Dataset.from_csv_file "#{DATA_DIR}/efsa.csv"
    datasets = [kazius,hansen,efsa]
    map = {"1" => "mutagen", "0" => "nonmutagen"}
    p "merging"
    training_dataset = Dataset.merge datasets: datasets, features: datasets.collect{|d| d.bioactivity_features.first}, value_maps: [nil,map,map], keep_original_features: false, remove_duplicates: true
    assert_equal 8281, training_dataset.compounds.size
    p training_dataset.features.size
    p training_dataset.id
    training_dataset = Dataset.find('5bd8ac8fca62695d767fca6b')
    p "create model_validation"
    model_validation = Model::Validation.from_dataset training_dataset: training_dataset, prediction_feature: training_dataset.merged_features.first, species: "Salmonella typhimurium", endpoint: "Mutagenicity"
    p model_validation.id
    p "predict"
    pa = Dataset.from_sdf_file "#{DATA_DIR}/PA.sdf"
    prediction_dataset = model_dataset.predict pa
    p prediction_dataset.id
    puts prediction_dataset.to_csv
  end

  def test_public_models
    skip
=begin
    #classification
    aids = [
      1205, #Rodents (multiple species/sites)
      1208, # rat carc
      1199 # mouse
      # Mutagenicity


      1195 #MRDD
      1188 #FHM
      1208, # rat carc td50
      1199 # mouse td50
    
    # daphnia
    # Blood Brain Barrier Penetration
    # Lowest observed adverse effect level (LOAEL)

      # 1204  estrogen receptor
      # 1259408, # GENE-TOX
      # 1159563 HepG2 cytotoxicity assay
      # 588209 hepatotoxicity
      # 1259333 cytotoxicity
      # 1159569 HepG2 cytotoxicity counterscreen Measured in Cell-Based System Using Plate Reader - 2153-03_Inhibitor_Dose_DryPowder_Activity
      # 2122 HTS Counterscreen for Detection of Compound Cytotoxicity in MIN6 Cells
      # 116724 Acute toxicity determined after intravenal administration in mice
      # 1148549 Toxicity in po dosed mouse assessed as mortality after 7 days
=end

  end
end
