require_relative "setup.rb"

class NanoparticleTest  < MiniTest::Test

  def test_import
    dataset_ids = Import::Enanomapper.import
    assert_operator Nanoparticle.count , :>, 570, "Only #{Nanoparticle.count} nanoparticles imported"
    assert_operator dataset_ids.size, :>, 8, "Only #{dataset_ids.size} bundles imported"
    assert dataset_ids.collect{|d| Dataset.find(d).name}.include? ("NanoWiki")
    assert dataset_ids.collect{|d| Dataset.find(d).name}.include? ("Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    p dataset_ids.collect{|d| {d => Dataset.find(d).name}}
    dataset_ids.collect do |d|
      d = Dataset.find(d)
      p d.name
      puts d.to_csv
    end
  end

  def test_export
    Dataset.all.each do |d|
      puts d.to_csv
    end
  end

  def test_create_model
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    model = Model::LazarRegression.create(training_dataset, :prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression", :neighbor_algorithm => "nanoparticle_neighbors")
    nanoparticle = training_dataset.nanoparticles[-34]
    prediction = model.predict nanoparticle
    p prediction
    refute_nil prediction[:value]
  end

end
