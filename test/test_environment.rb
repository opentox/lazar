require_relative "setup.rb"

class EnvironmentTest < MiniTest::Test
  def test_lazar_environment
    assert_equal "development", ENV["LAZAR_ENV"]
    assert_equal "development", ENV["MONGOID_ENV"]
    assert_equal "development", ENV["RACK_ENV"]
    assert_equal "development", Mongoid.clients["default"]["database"]
  end
end
