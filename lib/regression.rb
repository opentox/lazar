module OpenTox
  module Algorithm
    
    # TODO add LOO errors
    class Regression

      def self.weighted_average compound, params
        weighted_sum = 0.0
        sim_sum = 0.0
        confidence = 0.0
        neighbors = params[:neighbors]
        neighbors.each do |row|
          sim = row["tanimoto"]
          confidence = sim if sim > confidence # distance to nearest neighbor
          row["features"][params[:prediction_feature_id].to_s].each do |act|
            weighted_sum += sim*Math.log10(act)
            sim_sum += sim
          end
        end
        confidence = 0 if confidence.nan?
        sim_sum == 0 ? prediction = nil : prediction = 10**(weighted_sum/sim_sum)
        {:value => prediction,:confidence => confidence}
      end

      def self.local_pls_regression  compound, params
        neighbors = params[:neighbors]
        return {:value => nil, :confidence => nil, :warning => "No similar compounds in the training data"} unless neighbors.size > 0
        activities = []
        fingerprints = {}
        weights = []
        fingerprint_ids = neighbors.collect{|row| Compound.find(row["_id"]).fingerprint}.flatten.uniq.sort
        
        neighbors.each_with_index do |row,i|
          neighbor = Compound.find row["_id"]
          fingerprint = neighbor.fingerprint
          row["features"][params[:prediction_feature_id].to_s].each do |act|
            activities << Math.log10(act)
            weights << row["tanimoto"]
            fingerprint_ids.each_with_index do |id,j|
              fingerprints[id] ||= []
              fingerprints[id] << fingerprint.include?(id) 
            end
          end
        end

        name = Feature.find(params[:prediction_feature_id]).name
        R.assign "activities", activities
        R.assign "weights", weights
        variables = []
        data_frame = ["c(#{activities.join ","})"]
        fingerprints.each do |k,v| 
          unless v.uniq.size == 1
            data_frame << "factor(c(#{v.collect{|m| m ? "T" : "F"}.join ","}))"
            variables << k
          end
        end
        if variables.empty?
            result = weighted_average(compound, params)
            result[:warning] = "No variables for regression model. Using weighted average of similar compounds."
            return result
          return {:value => nil, :confidence => nil} # TODO confidence
        else
          R.eval "data <- data.frame(#{data_frame.join ","})"
          R.assign "features", variables
          R.eval "names(data) <- append(c('activities'),features)" #
          begin
            R.eval "model <- plsr(activities ~ .,data = data, ncomp = 4, weights = weights)"
          rescue # fall back to weighted average
            result = weighted_average(compound, params)
            result[:warning] = "Could not create local PLS model. Using weighted average of similar compounds."
            return result
          end
          #begin
            #compound_features = fingerprint_ids.collect{|f| compound.fingerprint.include? f } # FIX
            compound_features = variables.collect{|f| compound.fingerprint.include? f } 
            R.eval "fingerprint <- rbind(c(#{compound_features.collect{|f| f ? "T" : "F"}.join ','}))"
            R.eval "names(fingerprint) <- features" #
            R.eval "prediction <- predict(model,fingerprint)"
            prediction = 10**R.eval("prediction").to_f
            return {:value => prediction, :confidence => 1} # TODO confidence
          #rescue
            #p "Prediction failed"
            #return {:value => nil, :confidence => nil} # TODO confidence
          #end
        end
      
      end

      def self.local_physchem_regression  compound, params

        neighbors = params[:neighbors]
        return {:value => nil, :confidence => nil, :warning => "No similar compounds in the training data"} unless neighbors.size > 0
        return {:value => neighbors.first["features"][params[:prediction_feature_id]], :confidence => nil, :warning => "Only one similar compound in the training set"} unless neighbors.size > 1

        activities = []
        weights = []
        physchem = {}
        
        neighbors.each_with_index do |row,i|
          neighbor = Compound.find row["_id"]
          row["features"][params[:prediction_feature_id].to_s].each do |act|
            activities << Math.log10(act)
            weights << row["tanimoto"] # TODO cosine ?
            neighbor.physchem.each do |pid,v| # insert physchem only if there is an activity
              physchem[pid] ||= []
              physchem[pid] <<  v
            end
          end
        end

        # remove properties with a single value
        physchem.each do |pid,v|
          physchem.delete(pid) if v.uniq.size <= 1
        end

        if physchem.empty?
          result = weighted_average(compound, params)
          result[:warning] = "No variables for regression model. Using weighted average of similar compounds."
          return result
        else

          name = Feature.find(params[:prediction_feature_id]).name
          R.assign "weights", weights
          data_frame = ["c(#{activities.join ","})"]
          physchem.keys.each do |pid| 
            data_frame << "c(#{physchem[pid].join ","})" 
          end
          R.eval "data <- data.frame(#{data_frame.join ","})"
          R.assign "features", physchem.keys
          R.eval "names(data) <- append(c('activities'),features)" #
          begin
            R.eval "model <- plsr(activities ~ .,data = data, ncomp = 4, weights = weights)"
          rescue # fall back to weighted average
            result = weighted_average(compound, params)
            result[:warning] = "Could not create local PLS model. Using weighted average of similar compounds."
            return result
          end
          compound_features = physchem.keys.collect{|pid| compound.physchem[pid]}
          R.eval "fingerprint <- rbind(c(#{compound_features.join ','}))"
          R.eval "names(fingerprint) <- features" #
          R.eval "prediction <- predict(model,fingerprint)"
          prediction = 10**R.eval("prediction").to_f
          return {:value => prediction, :confidence => 1} # TODO confidence
        end
      
      end

      def self.weighted_average_with_relevant_fingerprints neighbors
        weighted_sum = 0.0
        sim_sum = 0.0
        fingerprint_features = []
        neighbors.each do |row|
          n,sim,acts = row
          neighbor = Compound.find n
          fingerprint_features += neighbor.fp4
        end
        fingerprint_features.uniq!
        p fingerprint_features
=begin
          p n
          acts.each do |act|
            weighted_sum += sim*Math.log10(act)
            sim_sum += sim
          end
        end
=end
        confidence = sim_sum/neighbors.size.to_f
        sim_sum == 0 ? prediction = nil : prediction = 10**(weighted_sum/sim_sum)
        {:value => prediction,:confidence => confidence}
      end

      # Local support vector regression from neighbors 
      # @param [Hash] params Keys `:props, :activities, :sims, :min_train_performance` are required
      # @return [Numeric] A prediction value.
      def self.local_svm_regression neighbors, params={:min_train_performance => 0.1}

        confidence = 0.0
        prediction = nil

        $logger.debug "Local SVM."
        props = neighbors.collect{|row| row[3] }
        neighbors.shift
        activities = neighbors.collect{|n| n[2]}
        prediction = self.local_svm_prop( props, activities, params[:min_train_performance]) # params[:props].nil? signals non-prop setting
        prediction = nil if (!prediction.nil? && prediction.infinite?)
        $logger.debug "Prediction: '#{prediction}' ('#{prediction.class}')."
        if prediction
          confidence = get_confidence({:sims => neighbors.collect{|n| n[1]}, :activities => activities})
        else
          confidence = nil if prediction.nil?
        end
          [prediction, confidence]

      end


      # Local support vector prediction from neighbors. 
      # Uses propositionalized setting.
      # Not to be called directly (use local_svm_regression or local_svm_classification).
      # @param [Array] props, propositionalization of neighbors and query structure e.g. [ Array_for_q, two-nested-Arrays_for_n ]
      # @param [Array] activities, activities for neighbors.
      # @param [Float] min_train_performance, parameter to control censoring
      # @return [Numeric] A prediction value.
      def self.local_svm_prop(props, activities, min_train_performance)

        $logger.debug "Local SVM (Propositionalization / Kernlab Kernel)."
        n_prop = props[1..-1] # is a matrix, i.e. two nested Arrays.
        q_prop = props[0] # is an Array.

        prediction = nil
        if activities.uniq.size == 1
          prediction = activities[0]
        else
          t = Time.now
          #$logger.debug gram_matrix.to_yaml
          #@r = RinRuby.new(true,false) # global R instance leads to Socket errors after a large number of requests
          @r = Rserve::Connection.new#(true,false) # global R instance leads to Socket errors after a large number of requests
          rs = []
          ["caret", "doMC", "class"].each do |lib|
            #raise "failed to load R-package #{lib}" unless @r.void_eval "suppressPackageStartupMessages(library('#{lib}'))"
            rs << "suppressPackageStartupMessages(library('#{lib}'))"
          end
          #@r.eval "registerDoMC()" # switch on parallel processing
          rs << "registerDoMC()" # switch on parallel processing
          #@r.eval "set.seed(1)"
          rs << "set.seed(1)"
          $logger.debug "Loading R packages: #{Time.now-t}"
          t = Time.now
          p n_prop
          begin

            # set data
            rs << "n_prop <- c(#{n_prop.flatten.join(',')})"
            rs << "n_prop <- c(#{n_prop.flatten.join(',')})"
            rs << "n_prop_x_size <- c(#{n_prop.size})"
            rs << "n_prop_y_size <- c(#{n_prop[0].size})"
            rs << "y <- c(#{activities.join(',')})"
            rs << "q_prop <- c(#{q_prop.join(',')})"
            rs << "y = matrix(y)"
            rs << "prop_matrix = matrix(n_prop, n_prop_x_size, n_prop_y_size, byrow=T)"
            rs << "q_prop = matrix(q_prop, 1, n_prop_y_size, byrow=T)"

            $logger.debug "Setting R data: #{Time.now-t}"
            t = Time.now
            # prepare data
            rs << "
              weights=NULL
              if (!(class(y) == 'numeric')) { 
                y = factor(y)
                weights=unlist(as.list(prop.table(table(y))))
                weights=(weights-1)^2
              }
            "

            rs << "
              rem = nearZeroVar(prop_matrix)
              if (length(rem) > 0) {
                prop_matrix = prop_matrix[,-rem,drop=F]
                q_prop = q_prop[,-rem,drop=F]
              }
              rem = findCorrelation(cor(prop_matrix))
              if (length(rem) > 0) {
                prop_matrix = prop_matrix[,-rem,drop=F]
                q_prop = q_prop[,-rem,drop=F]
              }
            "

            #p @r.eval("y").to_ruby
            #p "weights"
            #p @r.eval("weights").to_ruby
            $logger.debug "Preparing R data: #{Time.now-t}"
            t = Time.now
            # model + support vectors
            #train_success = @r.eval <<-EOR
            rs << '
              model = train(prop_matrix,y,
                             method="svmRadial",
                             preProcess=c("center", "scale"),
                             class.weights=weights,
                             trControl=trainControl(method="LGOCV",number=10),
                             tuneLength=8
                           )
              perf = ifelse ( class(y)!="numeric", max(model$results$Accuracy), model$results[which.min(model$results$RMSE),]$Rsquared )
            '
            File.open("/tmp/r.r","w+"){|f| f.puts rs.join("\n")}
            p rs.join("\n")
            p `Rscript /tmp/r.r`
=begin
            @r.void_eval <<-EOR
              model = train(prop_matrix,y,
                             method="svmRadial",
                             #preProcess=c("center", "scale"),
                             #class.weights=weights,
                             #trControl=trainControl(method="LGOCV",number=10),
                             #tuneLength=8
                           )
              perf = ifelse ( class(y)!='numeric', max(model$results$Accuracy), model$results[which.min(model$results$RMSE),]$Rsquared )
            EOR
=end

            $logger.debug "Creating R SVM model: #{Time.now-t}"
            t = Time.now
            if train_success
              # prediction
              @r.eval "predict(model,q_prop); p = predict(model,q_prop)" # kernlab bug: predict twice
              #@r.eval "p = predict(model,q_prop)" # kernlab bug: predict twice
              @r.eval "if (class(y)!='numeric') p = as.character(p)"
              prediction = @r.p

              # censoring
              prediction = nil if ( @r.perf.nan? || @r.perf < min_train_performance.to_f )
              prediction = nil if prediction =~ /NA/
              $logger.debug "Performance: '#{sprintf("%.2f", @r.perf)}'"
            else
              $logger.debug "Model creation failed."
              prediction = nil 
            end
            $logger.debug "R Prediction: #{Time.now-t}"
          rescue Exception => e
            $logger.debug "#{e.class}: #{e.message}"
            $logger.debug "Backtrace:\n\t#{e.backtrace.join("\n\t")}"
          ensure
            #puts @r.inspect
            #TODO: broken pipe
            #@r.quit # free R
          end
        end
        prediction
      end
    end

  end
end

