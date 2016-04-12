require_relative "setup.rb"

class NanoparticleTest  < MiniTest::Test

  def test_import
    Import::Enanomapper.import
    assert_operator Nanoparticle.count , :>, 570, "Only #{Nanoparticle.count} nanoparticles imported"
  end

  def test_create_model
    Model::NanoLazar.create_all.each do |model|
      np = Nanoparticle.find(model.training_particle_ids.sample)
      model.predict np
    end
  end

end
