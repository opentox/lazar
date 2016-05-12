module OpenTox
  module Algorithm
    
    class Regression

      def self.local_weighted_average substance, neighbors
        weighted_sum = 0.0
        sim_sum = 0.0
        neighbors.each do |neighbor|
          sim = neighbor["similarity"]
          activities = neighbor["toxicities"]
          activities.each do |act|
            weighted_sum += sim*act
            sim_sum += sim
          end if activities
        end
        sim_sum == 0 ? prediction = nil : prediction = weighted_sum/sim_sum
        {:value => prediction}
      end

      def self.local_fingerprint_regression substance, neighbors, method='pls'#, method_params="sigma=0.05"
        values = []
        fingerprints = {}
        weights = []
        fingerprint_ids = neighbors.collect{|n| Compound.find(n["_id"]).fingerprint}.flatten.uniq.sort

        neighbors.each do |n|
          fingerprint = Substance.find(n["_id"]).fingerprint
          activities = n["toxicities"]
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
          prediction = local_weighted_average substance, neighbors
          prediction[:warning] = "No variables for regression model. Using weighted average of similar substances."
          prediction
        else
          substance_features = variables.collect{|f| substance.fingerprint.include?(f) ? "T" : "F"} 
          prediction = r_model_prediction method, data_frame, variables, weights, substance_features
          if prediction.nil? or prediction[:value].nil?
            prediction = local_weighted_average substance, neighbors
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

      #def self.local_physchem_regression(substance:, neighbors:, feature_id:, dataset_id:, method: 'pls')#, method_params="ncomp = 4"
      def self.local_physchem_regression substance, neighbors, method='pls' #, method_params="ncomp = 4"

        #dataset = Dataset.find dataset_id
        activities = []
        weights = []
        pc_ids = neighbors.collect{|n| Substance.find(n["_id"]).physchem_descriptors.keys}.flatten.uniq
        data_frame = []
        data_frame[0] = []
        
        neighbors.each_with_index do |n,i|
          neighbor = Substance.find(n["_id"])
          activities = neighbor["toxicities"]
          activities.each do |act|
            data_frame[0][i] = act
            # TODO: update with cosine similarity for physchem
            weights << n["similarity"]
            neighbor.physchem_descriptors.each do |pid,values| 
              values = [values] unless values.is_a? Array
              values.uniq!
              warn "More than one value for '#{Feature.find(pid).name}': #{values.join(', ')}. Using the median." unless values.size == 1
              j = pc_ids.index(pid)+1
              data_frame[j] ||= []
              data_frame[j][i] = values.for_R
            end
          end if activities
          (0..pc_ids.size+1).each do |j| # for R: fill empty values with NA
            data_frame[j] ||= []
            data_frame[j][i] ||= "NA"
          end
        end
        remove_idx = []
        data_frame.each_with_index do |r,i|
          remove_idx << i if r.uniq.size == 1 # remove properties with a single value
        end
        remove_idx.reverse.each do |i|
          data_frame.delete_at i
          pc_ids.delete_at i
        end

        if pc_ids.empty?
          prediction = local_weighted_average substance, neighbors
          prediction[:warning] = "No variables for regression model. Using weighted average of similar substances."
          prediction
        else
          query_descriptors = pc_ids.collect do |i|
            substance.physchem_descriptors[i] ? substance.physchem_descriptors[i].for_R : "NA"
          end
          remove_idx = []
          query_descriptors.each_with_index do |v,i|
            remove_idx << i if v == "NA"
          end
          remove_idx.reverse.each do |i|
            data_frame.delete_at i
            pc_ids.delete_at i
            query_descriptors.delete_at i
          end
          prediction = r_model_prediction method, data_frame, pc_ids.collect{|i| "\"#{i}\""}, weights, query_descriptors
          if prediction.nil?
            prediction = local_weighted_average substance, neighbors
            prediction[:warning] = "Could not create local PLS model. Using weighted average of similar substances."
            prediction
          else
            prediction
          end
        end
      
      end

      def self.r_model_prediction method, training_data, training_features, training_weights, query_feature_values
        R.assign "weights", training_weights
        r_data_frame = "data.frame(#{training_data.collect{|r| "c(#{r.join(',')})"}.join(', ')})"
rlib = File.expand_path(File.join(File.dirname(__FILE__),"..","R"))
=begin
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
          R.eval "model <- train(activities ~ ., data = data, method = '#{method}', na.action = na.pass)"
          R.eval "fingerprint <- data.frame(rbind(c(#{query_feature_values.join ','})))"
          R.eval "names(fingerprint) <- features" 
          R.eval "prediction <- predict(model,fingerprint)"
          {
            :value => R.eval("prediction").to_f,
            :rmse => R.eval("getTrainPerf(model)$TrainRMSE").to_f,
            :r_squared => R.eval("getTrainPerf(model)$TrainRsquared").to_f,
          }
        rescue 
          return nil
        end
      end

    end
  end
end

