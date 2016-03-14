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
# should work on POSIX including os x
# http://stackoverflow.com/questions/19619582/number-of-processors-cores-in-command-line
NR_CORES = `getconf _NPROCESSORS_ONLN`.to_i
R = Rserve::Connection.new
R.eval "
suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(gridExtra)
  library(caret)
  library(doMC)
  registerDoMC(#{NR_CORES})
})
"

# Require sub-Repositories
require_relative '../openbabel/lib/openbabel'

# Fminer environment variables
ENV['FMINER_SMARTS'] = 'true'
ENV['FMINER_NO_AROMATIC'] = 'true'
ENV['FMINER_PVALUES'] = 'true'
ENV['FMINER_SILENT'] = 'true'
ENV['FMINER_NR_HITS'] = 'true'

# OpenTox classes and includes
CLASSES = ["Feature","Compound","Dataset","Validation","CrossValidation","LeaveOneOutValidation","RepeatedCrossValidation","Experiment"]# Algorithm and Models are modules

[ # be aware of the require sequence as it affects class/method overwrites
  "overwrite.rb",
  "rest-client-wrapper.rb", 
  "error.rb",
  "opentox.rb",
  "feature.rb",
  "physchem.rb",
  "compound.rb",
  "dataset.rb",
  "algorithm.rb",
  "model.rb",
  "classification.rb",
  "regression.rb",
  "validation.rb",
  "crossvalidation.rb",
  "leave-one-out-validation.rb",
  "experiment.rb",
].each{ |f| require_relative f }

