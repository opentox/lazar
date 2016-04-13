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
require 'openbabel'

# Environment setup
ENV["LAZAR_ENV"] ||= "production"
raise "Incorrect lazar environment variable LAZAR_ENV '#{ENV["LAZAR_ENV"]}', please set it to 'production' or 'development'." unless ENV["LAZAR_ENV"].match(/production|development/)

ENV["MONGOID_ENV"] = ENV["LAZAR_ENV"] 
ENV["RACK_ENV"] = ENV["LAZAR_ENV"] # should set sinatra environment
Mongoid.load_configuration({
  :clients => {
    :default => {
      :database => ENV["LAZAR_ENV"],
      :hosts => ["localhost:27017"],
    }
  }
})
Mongoid.raise_not_found_error = false # return nil if no document is found
$mongo = Mongo::Client.new("mongodb://127.0.0.1:27017/#{ENV['LAZAR_ENV']}")
$gridfs = $mongo.database.fs

# Logger setup
STDOUT.sync = true # for redirection, etc see http://stackoverflow.com/questions/8549443/why-doesnt-logger-output-to-stdout-get-redirected-to-files
$logger = Logger.new STDOUT # STDERR did not work on my development machine (CH)
case ENV["LAZAR_ENV"]
when "production"
  $logger.level = Logger::WARN
  Mongo::Logger.level = Logger::WARN 
when "development"
  $logger.level = Logger::DEBUG
  Mongo::Logger.level = Logger::WARN 
end

# R setup
rlib = File.expand_path(File.join(File.dirname(__FILE__),"..","R"))
# should work on POSIX including os x
# http://stackoverflow.com/questions/19619582/number-of-processors-cores-in-command-line
NR_CORES = `getconf _NPROCESSORS_ONLN`.to_i
R = Rserve::Connection.new
R.eval "
suppressPackageStartupMessages({
  library(iterators,lib=\"#{rlib}\")
  library(foreach,lib=\"#{rlib}\")
  library(ggplot2,lib=\"#{rlib}\")
  library(grid,lib=\"#{rlib}\")
  library(gridExtra,lib=\"#{rlib}\")
  library(pls,lib=\"#{rlib}\")
  library(caret,lib=\"#{rlib}\")
  library(doMC,lib=\"#{rlib}\")
  registerDoMC(#{NR_CORES})
})
"

# OpenTox classes and includes
#CLASSES = ["Feature","Substance::Compound","Substance::Nanoparticle","Dataset","Validation","CrossValidation","LeaveOneOutValidation","RepeatedCrossValidation","Experiment"]# Algorithm and Models are modules
CLASSES = ["Feature","Substance","Dataset","LazarPrediction","Validation","CrossValidation","LeaveOneOutValidation","RepeatedCrossValidation","Experiment"]# Algorithm and Models are modules

[ # be aware of the require sequence as it affects class/method overwrites
  "overwrite.rb",
  "rest-client-wrapper.rb", 
  "error.rb",
  "opentox.rb",
  "feature.rb",
  "physchem.rb",
  "substance.rb",
  "compound.rb",
  "nanoparticle.rb",
  "dataset.rb",
  "algorithm.rb",
  "model.rb",
  "classification.rb",
  "regression.rb",
  "validation.rb",
  "crossvalidation.rb",
  "leave-one-out-validation.rb",
  "validation-statistics.rb",
  "experiment.rb",
  "import.rb",
].each{ |f| require_relative f }
OpenTox::PhysChem.descriptors # load descriptor features
