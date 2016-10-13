module OpenTox
  module Algorithm
    
    class Caret
      # TODO classification
      # model list: https://topepo.github.io/caret/modelList.html

      def self.create_model_and_predict dependent_variables:, independent_variables:, weights:, method:, query_variables:
        if independent_variables.flatten.uniq == ["NA"] 
          prediction = Algorithm::Regression::weighted_average dependent_variables:dependent_variables, weights:weights
          prediction[:warning] = "No variables for regression model. Using weighted average of similar substances."
        else
          dependent_variables.each_with_index do |v,i| 
            dependent_variables[i] = to_r(v)
          end
          independent_variables.each_with_index do |c,i| 
            c.each_with_index do |v,j|
              independent_variables[i][j] = to_r(v)
            end
          end
          query_variables.each_with_index do |v,i| 
            query_variables[i] = to_r(v)
          end
          begin
            R.assign "weights", weights
            r_data_frame = "data.frame(#{([dependent_variables]+independent_variables).collect{|r| "c(#{r.join(',')})"}.join(', ')})"
            R.eval "data <- #{r_data_frame}"
            R.assign "features", (0..independent_variables.size-1).to_a
            R.eval "names(data) <- append(c('activities'),features)" #
            R.eval "model <- train(activities ~ ., data = data, method = '#{method}', na.action = na.pass, allowParallel=TRUE)"
          rescue => e
            $logger.debug "R caret model creation error for:"
            $logger.debug dependent_variables
            $logger.debug independent_variables
            return {:value => nil, :warning => "R caret model cration error."}
          end
          begin
            R.eval "query <- data.frame(rbind(c(#{query_variables.join ','})))"
            R.eval "names(query) <- features" 
            R.eval "prediction <- predict(model,query)"
            value = R.eval("prediction").to_f
            rmse = R.eval("getTrainPerf(model)$TrainRMSE").to_f
            r_squared = R.eval("getTrainPerf(model)$TrainRsquared").to_f
            prediction_interval = value-1.96*rmse, value+1.96*rmse
            prediction = {
              :value => value,
              :rmse => rmse,
              :r_squared => r_squared,
              :prediction_interval => prediction_interval
            }
          rescue => e
            $logger.debug "R caret prediction error for:"
            $logger.debug self.inspect
            return nil
          end
          if prediction.nil? or prediction[:value].nil?
            prediction = Algorithm::Regression::weighted_average dependent_variables:dependent_variables, weights:weights
            prediction[:warning] = "Could not create local caret model. Using weighted average of similar substances."
          end
        end
        prediction

      end

      # call caret methods dynamically, e.g. Caret.pls
      def self.method_missing(sym, *args, &block)
        args.first[:method] = sym.to_s
        self.create_model_and_predict args.first
      end

      def self.to_r v
        return "F" if v == false
        return "T" if v == true
        return nil if v.is_a? Float and v.nan?
        v
      end

    end
  end
end

