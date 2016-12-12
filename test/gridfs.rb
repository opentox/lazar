require_relative "setup.rb"

class GridFSTest < MiniTest::Test

  def test_gridfs
    file = Mongo::Grid::File.new("TEST", :filename => "test.txt",:content_type => "text/plain")
    id = $gridfs.insert_one file
    refute_nil id
  end
end
