module OpenTox
  module Algorithm
    
    class Regression

      def self.weighted_average descriptors:nil, neighbors:, parameters:nil
        # TODO: prediction_interval
        weighted_sum = 0.0
        sim_sum = 0.0
        neighbors.each do |neighbor|
          sim = neighbor["similarity"]
          activities = neighbor["measurements"]
          activities.each do |act|
            weighted_sum += sim*act
            sim_sum += sim
          end if activities
        end
        sim_sum == 0 ? prediction = nil : prediction = weighted_sum/sim_sum
        {:value => prediction}
      end

      def self.caret descriptors:, neighbors:, method: "pls", parameters:nil
        values = []
        descriptors = {}
        weights = []
        descriptor_ids = neighbors.collect{|n| n["descriptors"]}.flatten.uniq.sort

        neighbors.each do |n|
          activities = n["measurements"]
          activities.each do |act|
            values << act
            weights << n["similarity"]
            descriptor_ids.each do |id|
              descriptors[id] ||= []
              descriptors[id] << n["descriptors"].include?(id) 
            end
          end if activities
        end

        variables = []
        data_frame = [values]

        descriptors.each do |k,v| 
          unless v.uniq.size == 1
            data_frame << v.collect{|m| m ? "T" : "F"}
            variables << k
          end
        end

        if variables.empty?
          prediction = weighted_average(descriptors: descriptors, neighbors: neighbors)
          prediction[:warning] = "No variables for regression model. Using weighted average of similar substances."
          prediction
        else
          substance_features = variables.collect{|f| descriptors.include?(f) ? "T" : "F"} 
          #puts data_frame.to_yaml
          prediction = r_model_prediction method, data_frame, variables, weights, substance_features
          if prediction.nil? or prediction[:value].nil?
            prediction = weighted_average(descriptors: descriptors, neighbors: neighbors)
            prediction[:warning] = "Could not create local caret model. Using weighted average of similar substances."
            prediction
          else
            prediction[:prediction_interval] = [prediction[:value]-1.96*prediction[:rmse], prediction[:value]+1.96*prediction[:rmse]]
            prediction[:value] = prediction[:value]
            prediction[:rmse] = prediction[:rmse]
            prediction
          end
        end
      
      end

      def self.fingerprint_regression substance:, neighbors:, method: "pls" #, method_params="sigma=0.05"
        values = []
        fingerprints = {}
        weights = []
        fingerprint_ids = neighbors.collect{|n| Compound.find(n["_id"]).fingerprint}.flatten.uniq.sort

        neighbors.each do |n|
          fingerprint = Substance.find(n["_id"]).fingerprint
          activities = n["measurements"]
          activities.each do |act|
            values << act
            weights << n["similarity"]
            fingerprint_ids.each do |id|
              fingerprints[id] ||= []
              fingerprints[id] << fingerprint.include?(id) 
            end
          end if activities
        end

        variables = []
        data_frame = [values]

        fingerprints.each do |k,v| 
          unless v.uniq.size == 1
            data_frame << v.collect{|m| m ? "T" : "F"}
            variables << k
          end
        end

        if variables.empty?
          prediction = weighted_average(substance: substance, neighbors: neighbors)
          prediction[:warning] = "No variables for regression model. Using weighted average of similar substances."
          prediction
        else
          substance_features = variables.collect{|f| substance.fingerprint.include?(f) ? "T" : "F"} 
          prediction = r_model_prediction method, data_frame, variables, weights, substance_features
          if prediction.nil? or prediction[:value].nil?
            prediction = weighted_average(substance: substance, neighbors: neighbors)
            prediction[:warning] = "Could not create local PLS model. Using weighted average of similar substances."
            prediction
          else
            prediction[:prediction_interval] = [prediction[:value]-1.96*prediction[:rmse], prediction[:value]+1.96*prediction[:rmse]]
            prediction[:value] = prediction[:value]
            prediction[:rmse] = prediction[:rmse]
            prediction
          end
        end
      
      end

=begin
      def self.physchem_regression substance:, neighbors:, method: "pls"

        activities = []
        weights = []
        pc_ids = neighbors.collect{|n| n["common_descriptors"].collect{|d| d[:id]}}.flatten.uniq.sort
        data_frame = []
        data_frame[0] = []
        
        neighbors.each_with_index do |n,i|
          activities = n["measurements"]
          activities.each do |act|
            data_frame[0][i] = act
            weights << n["similarity"]
            n["common_descriptors"].each do |d| 
              j = pc_ids.index(d[:id])+1
              data_frame[j] ||= []
              data_frame[j][i] = d[:scaled_value]
            end
          end if activities
          (0..pc_ids.size).each do |j| # for R: fill empty values with NA
            data_frame[j] ||= []
            data_frame[j][i] ||= "NA"
          end
        end

        data_frame = data_frame.each_with_index.collect do |r,i|
          if r.uniq.size == 1 # remove properties with a single value 
            r = nil
            pc_ids[i-1] = nil # data_frame frame has additional activity entry
          end
          r
        end
        data_frame.compact!
        pc_ids.compact!

        if pc_ids.empty?
          prediction = weighted_average(substance: substance, neighbors: neighbors)
          prediction[:warning] = "No relevant variables for regression model. Using weighted average of similar substances."
          prediction
        else
          query_descriptors = pc_ids.collect { |i| substance.scaled_values[i] }
          query_descriptors = query_descriptors.each_with_index.collect do |v,i|
            unless v
              v = nil
              data_frame[i] = nil
              pc_ids[i] = nil
            end
            v
          end
          query_descriptors.compact!
          data_frame.compact!
          pc_ids.compact!
          prediction = r_model_prediction method, data_frame, pc_ids.collect{|i| "\"#{i}\""}, weights, query_descriptors
          if prediction.nil?
            prediction = weighted_average(substance: substance, neighbors: neighbors)
            prediction[:warning] = "Could not create local PLS model. Using weighted average of similar substances."
          end
          p prediction
          prediction
        end
      
      end
=end

      def self.r_model_prediction method, training_data, training_features, training_weights, query_feature_values
        R.assign "weights", training_weights
        r_data_frame = "data.frame(#{training_data.collect{|r| "c(#{r.join(',')})"}.join(', ')})"
=begin
rlib = File.expand_path(File.join(File.dirname(__FILE__),"..","R"))
        File.open("tmp.R","w+"){|f|
          f.puts "suppressPackageStartupMessages({
  library(iterators,lib=\"#{rlib}\")
  library(foreach,lib=\"#{rlib}\")
  library(ggplot2,lib=\"#{rlib}\")
  library(grid,lib=\"#{rlib}\")
  library(gridExtra,lib=\"#{rlib}\")
  library(pls,lib=\"#{rlib}\")
  library(caret,lib=\"#{rlib}\")
  library(doMC,lib=\"#{rlib}\")
  registerDoMC(#{NR_CORES})
})"

          f.puts "data <- #{r_data_frame}\n"
          f.puts "weights <- c(#{training_weights.join(', ')})"
          f.puts "features <- c(#{training_features.join(', ')})"
          f.puts "names(data) <- append(c('activities'),features)" #
          f.puts "ctrl <- rfeControl(functions = #{method}, method = 'repeatedcv', repeats = 5, verbose = T)"
          f.puts "lmProfile <- rfe(activities ~ ., data = data, rfeControl = ctrl)"

          f.puts "model <- train(activities ~ ., data = data, method = '#{method}')"
          f.puts "fingerprint <- data.frame(rbind(c(#{query_feature_values.join ','})))"
          f.puts "names(fingerprint) <- features" 
          f.puts "prediction <- predict(model,fingerprint)"
        }
=end
        
        R.eval "data <- #{r_data_frame}"
        R.assign "features", training_features
        begin
          R.eval "names(data) <- append(c('activities'),features)" #
          R.eval "model <- train(activities ~ ., data = data, method = '#{method}', na.action = na.pass, allowParallel=TRUE)"
          R.eval "fingerprint <- data.frame(rbind(c(#{query_feature_values.join ','})))"
          R.eval "names(fingerprint) <- features" 
          R.eval "prediction <- predict(model,fingerprint)"
          value = R.eval("prediction").to_f
          rmse = R.eval("getTrainPerf(model)$TrainRMSE").to_f
          r_squared = R.eval("getTrainPerf(model)$TrainRsquared").to_f
          prediction_interval = value-1.96*rmse, value+1.96*rmse
          {
            :value => value,
            :rmse => rmse,
            :r_squared => r_squared,
            :prediction_interval => prediction_interval
          }
        rescue 
          return nil
        end
      end

    end
  end
end

