require_relative "setup.rb"

class NanoparticleTest  < MiniTest::Test

  def test_import
    dataset_ids = Import::Enanomapper.import
    assert_operator Nanoparticle.count , :>, 570, "Only #{Nanoparticle.count} nanoparticles imported"
    assert_operator dataset_ids.size, :>, 8, "Only #{dataset_ids.size} bundles imported"
    p dataset_ids.collect{|d| Dataset.find(d).name}
    assert dataset_ids.collect{|d| Dataset.find(d).name}.include? ("NanoWiki")
    assert dataset_ids.collect{|d| Dataset.find(d).name}.include? ("Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
  end

  def test_create_model
    Model::NanoLazar.create_all.each do |model|
      np = Nanoparticle.find(model.training_particle_ids.sample)
      model.predict np
    end
  end

end
