require_relative "setup.rb"

class ValidationModelTest < MiniTest::Test

  def test_validation_model
    m = Model::Validation.from_csv_file "#{DATA_DIR}/hamster_carcinogenicity.csv"
    [:endpoint,:species,:source].each do |p|
      refute_empty m[p]
    end
    assert m.classification?
    refute m.regression?
    m.crossvalidations.each do |cv|
      assert cv.accuracy > 0.74, "Crossvalidation accuracy (#{cv.accuracy}) should be larger than 0.75. This may happen due to an unfavorable training/test set split."
    end
    prediction = m.predict Compound.from_smiles("OCC(CN(CC(O)C)N=O)O")
    assert_equal "true", prediction[:value]
    m.delete
  end
end
