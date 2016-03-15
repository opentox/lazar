module OpenTox
  module Algorithm
    
    class Regression

      def self.local_weighted_average compound, params
        weighted_sum = 0.0
        sim_sum = 0.0
        neighbors = params[:neighbors]
        neighbors.each do |row|
          sim = row["tanimoto"]
          if row["features"][params[:prediction_feature_id].to_s]
            row["features"][params[:prediction_feature_id].to_s].each do |act|
              weighted_sum += sim*Math.log10(act)
              sim_sum += sim
            end
          end
        end
        sim_sum == 0 ? prediction = nil : prediction = 10**(weighted_sum/sim_sum)
        {:value => prediction}
      end

      # TODO explicit neighbors, also for physchem
      def self.local_fingerprint_regression  compound, params, method='pls'#, method_params="sigma=0.05"
        neighbors = params[:neighbors]
        return {:value => nil, :confidence => nil, :warning => "No similar compounds in the training data"} unless neighbors.size > 0
        activities = []
        fingerprints = {}
        weights = []
        fingerprint_ids = neighbors.collect{|row| Compound.find(row["_id"]).fingerprint}.flatten.uniq.sort
        
        #p neighbors
        neighbors.each_with_index do |row,i|
          neighbor = Compound.find row["_id"]
          fingerprint = neighbor.fingerprint
          if row["features"][params[:prediction_feature_id].to_s]
            row["features"][params[:prediction_feature_id].to_s].each do |act|
              activities << Math.log10(act)
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
            prediction[:value] = 10**prediction[:value]
            prediction[:rmse] = 10**prediction[:rmse]
            prediction
          end
        end
      
      end

      def self.local_physchem_regression  compound, params, method="plsr"#, method_params="ncomp = 4"

        neighbors = params[:neighbors]
        return {:value => nil, :confidence => nil, :warning => "No similar compounds in the training data"} unless neighbors.size > 0
        return {:value => neighbors.first["features"][params[:prediction_feature_id]], :confidence => nil, :warning => "Only one similar compound in the training set"} unless neighbors.size > 1

        activities = []
        weights = []
        physchem = {}
        
        neighbors.each_with_index do |row,i|
          neighbor = Compound.find row["_id"]
          if row["features"][params[:prediction_feature_id].to_s]
            row["features"][params[:prediction_feature_id].to_s].each do |act|
              activities << Math.log10(act)
              weights << row["tanimoto"] # TODO cosine ?
              neighbor.physchem.each do |pid,v| # insert physchem only if there is an activity
                physchem[pid] ||= []
                physchem[pid] <<  v
              end
            end
          end
        end

        # remove properties with a single value
        physchem.each do |pid,v|
          physchem.delete(pid) if v.uniq.size <= 1
        end

        if physchem.empty?
          result = local_weighted_average(compound, params)
          result[:warning] = "No variables for regression model. Using weighted average of similar compounds."
          return result

        else
          data_frame = [activities] + physchem.keys.collect { |pid| physchem[pid] }
          prediction = r_model_prediction method, data_frame, physchem.keys, weights, physchem.keys.collect{|pid| compound.physchem[pid]}
          if prediction.nil?
            prediction = local_weighted_average(compound, params)
            prediction[:warning] = "Could not create local PLS model. Using weighted average of similar compounds."
            return prediction
          else
            prediction[:value] = 10**prediction[:value]
            prediction
          end
        end
      
      end

      def self.r_model_prediction method, training_data, training_features, training_weights, query_feature_values
        R.assign "weights", training_weights
        r_data_frame = "data.frame(#{training_data.collect{|r| "c(#{r.join(',')})"}.join(', ')})"
        R.eval "data <- #{r_data_frame}"
        R.assign "features", training_features
        R.eval "names(data) <- append(c('activities'),features)" #
        begin
          R.eval "model <- train(activities ~ ., data = data, method = '#{method}')"
        rescue 
          return nil
        end
        R.eval "fingerprint <- data.frame(rbind(c(#{query_feature_values.join ','})))"
        R.eval "names(fingerprint) <- features" 
        R.eval "prediction <- predict(model,fingerprint)"
        {
          :value => R.eval("prediction").to_f,
          :rmse => R.eval("getTrainPerf(model)$TrainRMSE").to_f,
          :r_squared => R.eval("getTrainPerf(model)$TrainRsquared").to_f,
        }
      end

    end
  end
end

