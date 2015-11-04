module OpenTox
  module Algorithm
    
    class Regression

      def self.weighted_average compound, params
        #p params.keys
        weighted_sum = 0.0
        sim_sum = 0.0
        confidence = 0.0
        neighbors = params[:neighbors]
        activities = []
        neighbors.each do |row|
          #if row["dataset_ids"].include? params[:training_dataset_id]
            sim = row["tanimoto"]
            confidence = sim if sim > confidence # distance to nearest neighbor
            # TODO add LOO errors
            row["features"][params[:prediction_feature_id].to_s].each do |act|
              weighted_sum += sim*Math.log10(act)
              activities << act
              sim_sum += sim
            end
          #end
        end
        #R.assign "activities", activities
        #R.eval "cv = cv(activities)"
        #confidence /= activities.standard_deviation#/activities.mean
        #confidence = sim_sum*neighbors.size.to_f/params[:training_dataset_size]
        #confidence = sim_sum/neighbors.size.to_f
        #confidence = neighbors.size.to_f
        confidence = 0 if confidence.nan?
        sim_sum == 0 ? prediction = nil : prediction = 10**(weighted_sum/sim_sum)
        {:value => prediction,:confidence => confidence}
      end

      def self.local_linear_regression  compound, neighbors
        return nil unless neighbors.size > 0
        features = neighbors.collect{|n| Compound.find(n.first).fp4}.flatten.uniq
        training_data = Array.new(neighbors.size){Array.new(features.size,0)}
        neighbors.each_with_index do |n,i|
          #p n.first
          neighbor = Compound.find n.first
          features.each_with_index do |f,j|
            training_data[i][j] = 1 if neighbor.fp4.include? f
          end
        end
        p training_data

        R.assign "activities", neighbors.collect{|n| n[2].median}
        R.assign "features", training_data
        R.eval "model <- lm(activities ~ features)"
        R.eval "summary <- summary(model)"
        p R.summary
        compound_features = features.collect{|f| compound.fp4.include? f ? 1 : 0}
        R.assign "compound_features", compound_features
        R.eval "prediction <- predict(model,compound_features)"
        p R.prediction
      
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

