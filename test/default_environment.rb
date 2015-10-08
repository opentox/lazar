require 'minitest/autorun'
require_relative '../lib/lazar.rb'
include OpenTox
class DefaultEnvironmentTest < MiniTest::Test
  def test_lazar_environment
    assert_equal "production", ENV["LAZAR_ENV"]
    assert_equal "production", ENV["MONGOID_ENV"]
    assert_equal "production", ENV["RACK_ENV"]
    assert_equal "production", Mongoid.clients["default"]["database"]
  end
end
