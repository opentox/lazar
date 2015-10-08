require 'minitest/autorun'
require_relative '../lib/lazar.rb'
include OpenTox
TEST_DIR ||= File.expand_path(File.dirname(__FILE__))
DATA_DIR ||= File.join(TEST_DIR,"data")
Mongoid.configure.connect_to("test")
$mongo = Mongo::Client.new('mongodb://127.0.0.1:27017/test')
#$mongo.database.drop
$gridfs = $mongo.database.fs
