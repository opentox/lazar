require_relative "setup.rb"

class LazarRpackagesTest < MiniTest::Test

  def test_user_packages_installed
    packages = ["caret", "randomForest", "ggplot2", "pls", "doMC", "gridExtra", "foreach", "iterators", "stringi"]
    packages.each do |p|
      r = R.eval "require(#{p})"
      assert_equal 1, r.payload[0]
    end
  end

end

