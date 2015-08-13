require 'rubygems'
require "bundler/setup"
require "rest-client"
require 'yaml'
require 'json'
require 'logger'
require 'mongoid'
require 'rserve'
require "nokogiri"
require "base64"


# Mongo setup
# TODO retrieve correct environment from Rack/Sinatra
ENV["MONGOID_ENV"] ||= "development"
# TODO remove config files, change default via ENV or directly in Mongoid class
Mongoid.load!("#{ENV['HOME']}/.opentox/config/mongoid.yml")
# TODO get Mongo::Client from Mongoid
$mongo = Mongo::Client.new('mongodb://127.0.0.1:27017/opentox')
# TODO same for GridFS
$gridfs = $mongo.database.fs

# R setup
R = Rserve::Connection.new

# Logger setup
$logger = Logger.new STDOUT # STDERR did not work on my development machine (CH)
$logger.level = Logger::DEBUG
Mongo::Logger.logger = $logger
Mongo::Logger.level = Logger::WARN 
#Mongoid.logger = $logger

# Require sub-Repositories
require_relative '../libfminer/libbbrc/bbrc' # include before openbabel
require_relative '../libfminer/liblast/last' # 
require_relative '../last-utils/lu.rb'
require 'openbabel'

# Fminer environment variables
ENV['FMINER_SMARTS'] = 'true'
ENV['FMINER_NO_AROMATIC'] = 'true'
ENV['FMINER_PVALUES'] = 'true'
ENV['FMINER_SILENT'] = 'true'
ENV['FMINER_NR_HITS'] = 'true'

# OpenTox classes and includes
CLASSES = ["Feature","Compound","Dataset","Validation","CrossValidation"]# Algorithm and Models are modules

[ # be aware of the require sequence as it affects class/method overwrites
  "overwrite.rb",
  "rest-client-wrapper.rb", 
  "error.rb",
  "opentox.rb",
  "feature.rb",
  "compound.rb",
  "dataset.rb",
  "descriptor.rb",
  "algorithm.rb",
  "descriptor.rb",
  "bbrc.rb",
  "lazar-model.rb",
  "similarity.rb",
  "neighbor.rb",
  "classification.rb",
  "regression.rb",
  "validation.rb",
  "crossvalidation.rb",
].each{ |f| require_relative f }
