module OpenTox
  module Algorithm
    
    # Ruby interface for the R caret package
    # Caret model list: https://topepo.github.io/caret/modelList.html
    class Caret

      # Create a local R caret model and make a prediction
      # @param [Array<Float,Bool>] dependent_variables
      # @param [Array<Array<Float,Bool>>] independent_variables
      # @param [Array<Float>] weights
      # @param [String] Caret method
      # @param [Array<Float,Bool>] query_variables
      # @return [Hash]
      def self.create_model_and_predict dependent_variables:, independent_variables:, weights:, method:, query_variables:
        remove = []
        # remove independent_variables with single values
        independent_variables.each_with_index { |values,i| remove << i if values.uniq.size == 1}
        remove.sort.reverse.each do |i|
          independent_variables.delete_at i
          query_variables.delete_at i
        end
        if independent_variables.flatten.uniq == ["NA"] or independent_variables.flatten.uniq == [] 
          prediction = Algorithm::Classification::weighted_majority_vote dependent_variables:dependent_variables, weights:weights
          prediction[:warnings] << "No variables for classification model. Using weighted average of similar substances."
        elsif dependent_variables.uniq.size == 1
          prediction = Algorithm::Classification::weighted_majority_vote dependent_variables:dependent_variables, weights:weights
          prediction[:warnings] << "All neighbors have the same measured activity. Cannot create random forest model, using weighted average of similar substances."
        elsif dependent_variables.size < 3
          prediction = Algorithm::Classification::weighted_majority_vote dependent_variables:dependent_variables, weights:weights
          prediction[:warnings] << "Insufficient number of neighbors (#{dependent_variables.size}) for classification model. Using weighted average of similar substances."
        else
          dependent_variables.collect!{|v| to_r(v)}
          independent_variables.each_with_index do |c,i| 
            c.each_with_index do |v,j|
              independent_variables[i][j] = to_r(v)
            end
          end
#          query_variables.collect!{|v| to_r(v)}
          begin
            R.assign "weights", weights
            #r_data_frame = "data.frame(#{([dependent_variables.collect{|v| to_r(v)}]+independent_variables).collect{|r| "c(#{r.collect{|v| to_r(v)}.join(',')})"}.join(', ')})"
            r_data_frame = "data.frame(#{([dependent_variables]+independent_variables).collect{|r| "c(#{r.join(',')})"}.join(', ')})"
            #p r_data_frame
            R.eval "data <- #{r_data_frame}"
            R.assign "features", (0..independent_variables.size-1).to_a
            R.eval "names(data) <- append(c('activities'),features)" #
            p "train"
            R.eval "model <- train(activities ~ ., data = data, method = '#{method}', na.action = na.pass, allowParallel=TRUE)"
            p "done"
          rescue => e
            $logger.debug "R caret model creation error for: #{e.message}"
            $logger.debug dependent_variables
            $logger.debug independent_variables
            prediction = Algorithm::Classification::weighted_majority_vote dependent_variables:dependent_variables, weights:weights
            prediction[:warnings] << "R caret model creation error. Using weighted average of similar substances."
            return prediction
          end
          begin
            R.eval "query <- data.frame(rbind(c(#{query_variables.collect{|v| to_r(v)}.join ','})))"
            R.eval "names(query) <- features" 
            R.eval "prediction <- predict(model,query, type=\"prob\")"
            names = R.eval("names(prediction)").to_ruby
            probs = R.eval("prediction").to_ruby
            probabilities = {}
            names.each_with_index { |n,i| probabilities[n] = probs[i] }
            value = probabilities.sort_by{|n,p| -p }[0][0]
            prediction = {
              :value => value,
              :probabilities => probabilities,
              :warnings => [],
            }
          rescue => e
            $logger.debug "R caret prediction error for: #{e.inspect}"
            $logger.debug self.inspect
            prediction = Algorithm::Classification::weighted_majority_vote dependent_variables:dependent_variables, weights:weights
            prediction[:warnings] << "R caret prediction error. Using weighted average of similar substances"
            return prediction
          end
          if prediction.nil? or prediction[:value].nil?
            prediction = Algorithm::Classification::weighted_majority_vote dependent_variables:dependent_variables, weights:weights
            prediction[:warnings] << "Empty R caret prediction. Using weighted average of similar substances."
          end
        end
        prediction

      end

      # Call caret methods dynamically, e.g. Caret.pls
      def self.method_missing(sym, *args, &block)
        args.first[:method] = sym.to_s
        self.create_model_and_predict args.first
      end

      # Convert Ruby values to R values
      def self.to_r v
        return "F" if v == false
        return "T" if v == true
        return nil if v.is_a? Float and v.nan?
        return "\"#{v}\"" if v.is_a? String
        v
      end

    end
  end
end

