module OpenTox
  module Algorithm
    
    class Caret
      # TODO classification
      # model list: https://topepo.github.io/caret/modelList.html

      attr_accessor :descriptors, :neighbors, :method, :relevant_features, :data_frame, :feature_names, :weights, :query_features

      def initialize descriptors:, neighbors:, method:, relevant_features:
        @descriptors = descriptors
        @neighbors = neighbors
        @method = method
        @relevant_features = relevant_features
      end

      def self.regression descriptors:, neighbors:, method:, relevant_features:nil 

        caret = new(descriptors:descriptors, neighbors:neighbors, method:method, relevant_features:relevant_features)
        # collect training data for R
        if descriptors.is_a? Array
          caret.fingerprint2R 
        elsif descriptors.is_a? Hash
          caret.properties2R
        else
          bad_request_error "Descriptors should be a fingerprint (Array) or properties (Hash). Cannot handle '#{descriptors.class}'."
        end
        if caret.feature_names.empty? or caret.data_frame.flatten.uniq == ["NA"]
          prediction = Algorithm::Regression::weighted_average(descriptors: @descriptors, neighbors: neighbors)
          prediction[:warning] = "No variables for regression model. Using weighted average of similar substances."
        else
          prediction = caret.r_model_prediction 
          if prediction.nil? or prediction[:value].nil?
            prediction = Algorithm::Regression::weighted_average(descriptors: @descriptors, neighbors: neighbors)
            prediction[:warning] = "Could not create local caret model. Using weighted average of similar substances."
          end
        end
        prediction

      end

      def fingerprint2R

        values = []
        features = {}
        @weights = []
        descriptor_ids = neighbors.collect{|n| n["descriptors"]}.flatten.uniq.sort

        neighbors.each do |n|
          activities = n["measurements"]
          activities.each do |act|
            values << act
            @weights << n["similarity"]
            descriptor_ids.each do |id|
              features[id] ||= []
              features[id] << n["descriptors"].include?(id) 
            end
          end if activities
        end

        @feature_names = []
        @data_frame = [values]

        features.each do |k,v| 
          unless v.uniq.size == 1
            @data_frame << v.collect{|m| m ? "T" : "F"}
            @feature_names << k
          end
        end
        @query_features = @feature_names.collect{|f| descriptors.include?(f) ? "T" : "F"} 

      end


      def properties2R 

        @weights = []
        @feature_names = []
        @query_features = []

        # keep only descriptors with values
        @relevant_features.keys.each_with_index do |f,i|
          if @descriptors[f]
            @feature_names << f
            @query_features << @descriptors[f].median
          else
            neighbors.each do |n|
              n["descriptors"].delete_at i
            end
          end
        end
        
        measurements = neighbors.collect{|n| n["measurements"]}.flatten 
        # initialize data frame with 'NA' defaults
        @data_frame = Array.new(@feature_names.size+1){Array.new(measurements.size,"NA") }

        i = 0
        # parse neighbor activities and descriptors
        neighbors.each do |n|
          activities = n["measurements"]
          activities.each do |act| # multiple measurements are treated as separate instances
            unless n["descriptors"].include?(nil)
              data_frame[0][i] = act
              @weights << n["similarity"]
              n["descriptors"].each_with_index do |d,j| 
                @data_frame[j+1][i] = d
              end
              i += 1
            end
          end if activities # ignore neighbors without measurements
        end

      end

      def r_model_prediction 
        begin
          R.assign "weights", @weights
          r_data_frame = "data.frame(#{@data_frame.collect{|r| "c(#{r.join(',')})"}.join(', ')})"
          R.eval "data <- #{r_data_frame}"
          R.assign "features", @feature_names
          R.eval "names(data) <- append(c('activities'),features)" #
          R.eval "model <- train(activities ~ ., data = data, method = '#{method}', na.action = na.pass, allowParallel=TRUE)"
        rescue => e
          $logger.debug "R caret model creation error for:"
          $logger.debug JSON.pretty_generate(self.inspect)
          return nil
        end
        begin
          R.eval "query <- data.frame(rbind(c(#{@query_features.join ','})))"
          R.eval "names(query) <- features" 
          R.eval "prediction <- predict(model,query)"
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
        rescue => e
          $logger.debug "R caret prediction error for:"
          $logger.debug self.inspect
          return nil
        end
      end

    end
  end
end

