require_relative "setup.rb"

class NanoparticleTest  < MiniTest::Test

  MODENA = File.join DATA_DIR,"MODENA-EC50_EC25.csv"

  def test_import
    Import::Enanomapper.import
    assert_operator Nanoparticle.count , :>, 570, "Only #{Nanoparticle.count} nanoparticles imported"
  end

end
