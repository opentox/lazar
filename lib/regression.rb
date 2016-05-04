module OpenTox
  module Algorithm
    
    class Regression

      def self.local_weighted_average compound, params
        weighted_sum = 0.0
        sim_sum = 0.0
        neighbors = params[:neighbors]
        neighbors.each do |row|
          sim = row["tanimoto"]
          sim ||= 1 # TODO: sim f nanoparticles
          if row["toxicities"][params[:prediction_feature_id].to_s]
            row["toxicities"][params[:prediction_feature_id].to_s].each do |act|
              weighted_sum += sim*act
              sim_sum += sim
            end
          end
        end
        sim_sum == 0 ? prediction = nil : prediction = weighted_sum/sim_sum
        {:value => prediction}
      end

      def self.local_fingerprint_regression  compound, params, method='pls'#, method_params="sigma=0.05"
        neighbors = params[:neighbors]
        return {:value => nil, :confidence => nil, :warning => "No similar compounds in the training data"} unless neighbors.size > 0
        activities = []
        fingerprints = {}
        weights = []
        fingerprint_ids = neighbors.collect{|row| Compound.find(row["_id"]).fingerprint}.flatten.uniq.sort
        
        neighbors.each_with_index do |row,i|
          neighbor = Compound.find row["_id"]
          fingerprint = neighbor.fingerprint
          if row["toxicities"][params[:prediction_feature_id].to_s]
            row["toxicities"][params[:prediction_feature_id].to_s].each do |act|
              activities << act
              weights << row["tanimoto"]
              fingerprint_ids.each_with_index do |id,j|
                fingerprints[id] ||= []
                fingerprints[id] << fingerprint.include?(id) 
              end
            end
          end
        end

        variables = []
        data_frame = [activities]
        fingerprints.each do |k,v| 
          unless v.uniq.size == 1
            data_frame << v.collect{|m| m ? "T" : "F"}
            variables << k
          end
        end

        if variables.empty?
            result = local_weighted_average(compound, params)
            result[:warning] = "No variables for regression model. Using weighted average of similar compounds."
            return result

        else
          compound_features = variables.collect{|f| compound.fingerprint.include?(f) ? "T" : "F"} 
          prediction = r_model_prediction method, data_frame, variables, weights, compound_features
          if prediction.nil? or prediction[:value].nil?
            prediction = local_weighted_average(compound, params)
            prediction[:warning] = "Could not create local PLS model. Using weighted average of similar compounds."
            return prediction
          else
            prediction[:prediction_interval] = [prediction[:value]-1.96*prediction[:rmse], prediction[:value]+1.96*prediction[:rmse]]
            prediction[:value] = prediction[:value]
            prediction[:rmse] = prediction[:rmse]
            prediction
          end
        end
      
      end

      def self.local_physchem_regression  compound, params, method="pls"#, method_params="ncomp = 4"

        neighbors = params[:neighbors].select{|n| n["toxicities"][params[:prediction_feature_id].to_s]} # use only neighbors with measured activities

        return {:value => nil, :confidence => nil, :warning => "No similar compounds in the training data"} unless neighbors.size > 0
        return {:value => neighbors.first["toxicities"][params[:prediction_feature_id]], :confidence => nil, :warning => "Only one similar compound in the training set"} unless neighbors.size > 1

        activities = []
        weights = []
        pc_ids = neighbors.collect{|n| Substance.find(n["_id"]).physchem_descriptors.keys}.flatten.uniq
        data_frame = []
        data_frame[0] = []
        
        neighbors.each_with_index do |n,i|
          neighbor = Substance.find(n["_id"])
          n["toxicities"][params[:prediction_feature_id].to_s].each do |act|
            data_frame[0][i] = act
            n["tanimoto"] ?  weights << n["tanimoto"] : weights << 1.0 # TODO cosine ?
            neighbor.physchem_descriptors.each do |pid,values| 
              values.uniq!
              warn "More than one value for '#{Feature.find(pid).name}': #{values.join(', ')}. Using the median." unless values.size == 1
              j = pc_ids.index(pid)+1
              data_frame[j] ||= []
              data_frame[j][i] = values.for_R
            end
          end
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
          result = local_weighted_average(compound, params)
          result[:warning] = "No variables for regression model. Using weighted average of similar compounds."
          return result
        else
          query_descriptors = pc_ids.collect do |i|
            compound.physchem_descriptors[i] ? compound.physchem_descriptors[i].for_R : "NA"
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
            prediction = local_weighted_average(compound, params)
            prediction[:warning] = "Could not create local PLS model. Using weighted average of similar compounds."
            return prediction
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

