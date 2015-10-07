require_relative "setup.rb"

class PredictionModelTest < MiniTest::Test

  def test_prediction_model
    pm = Model::Prediction.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    #dataset = Dataset.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    #model = Model::LazarFminerClassification.create dataset
    #cv = ClassificationCrossValidation.create model
    #metadata = JSON.parse(File.read("#{DATA_DIR}/hamster_carcinogenicity.json"))

    #metadata[:model_id] = model.id
    #metadata[:crossvalidation_id] = cv.id
    #pm = Model::Prediction.new(metadata)
    #pm.save
    [:endpoint,:species,:source].each do |p|
      refute_empty pm[p]
    end
    assert pm.classification?
    refute pm.regression?
    pm.crossvalidations.each do |cv|
      assert cv.accuracy > 0.75
    end
    prediction = pm.predict Compound.from_smiles("CCCC(NN)C")
    assert_equal "true", prediction[:value]
    pm.delete
  end
end
