require 'rubygems'
require "bundler/setup"
require "rest-client"
require 'addressable'
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
# search for a central mongo database in use
# http://opentox.github.io/installation/2017/03/07/use-central-mongodb-in-docker-environment
CENTRAL_MONGO_IP = "mongodb"
Mongoid.load_configuration({
  :clients => {
    :default => {
      :database => ENV["LAZAR_ENV"],
      :hosts => (CENTRAL_MONGO_IP.blank? ? ["localhost:27017"] : ["#{CENTRAL_MONGO_IP}:27017"]),
    }
  }
})
Mongoid.raise_not_found_error = false # return nil if no document is found
$mongo = Mongo::Client.new("mongodb://#{(CENTRAL_MONGO_IP.blank? ? "127.0.0.1" : CENTRAL_MONGO_IP)}:27017/#{ENV['LAZAR_ENV']}")
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
R = Rserve::Connection.new
R.eval ".libPaths('#{rlib}')"
R.eval "
suppressPackageStartupMessages({
  library(labeling,lib=\"#{rlib}\")
  library(iterators,lib=\"#{rlib}\")
  library(foreach,lib=\"#{rlib}\")
  library(ggplot2,lib=\"#{rlib}\")
  library(grid,lib=\"#{rlib}\")
  library(gridExtra,lib=\"#{rlib}\")
  library(pls,lib=\"#{rlib}\")
  library(caret,lib=\"#{rlib}\")
  library(doMC,lib=\"#{rlib}\")
  library(randomForest,lib=\"#{rlib}\")
  library(plyr,lib=\"#{rlib}\")
})
"
# OpenTox classes and includes
CLASSES = ["Feature","Substance","Dataset","LazarPrediction","CrossValidation","LeaveOneOutValidation","RepeatedCrossValidation","Experiment"]# Algorithm and Models are modules

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
  "similarity.rb",
  "feature_selection.rb",
  "model.rb",
  "classification.rb",
  "regression.rb",
  "caret.rb",
  "validation-statistics.rb",
  "validation.rb",
  "train-test-validation.rb",
  "leave-one-out-validation.rb",
  "crossvalidation.rb",
  #"experiment.rb",
  "import.rb",
].each{ |f| require_relative f }
