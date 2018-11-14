require_relative "setup.rb"

class ErrorTest < MiniTest::Test

  def test_bad_request
    object = OpenTox::Feature.new 
    assert_nil OpenTox::Feature.find(object.id)
  end

  def test_exception
    assert_raises Exception do
      raise Exception.new "Basic Exception"
    end
  end

end
