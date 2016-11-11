ENV["LAZAR_ENV"] = "development"
require 'minitest/autorun'
require_relative '../lib/lazar.rb'
#require 'lazar'
include OpenTox
TEST_DIR ||= File.expand_path(File.dirname(__FILE__))
DATA_DIR ||= File.join(TEST_DIR,"data")
training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
unless training_dataset
  Import::Enanomapper.import File.join(File.dirname(__FILE__),"data","enm")
end
#$mongo.database.drop
#$gridfs = $mongo.database.fs
