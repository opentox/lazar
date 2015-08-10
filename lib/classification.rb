module OpenTox
  module Algorithm
    
    class Classification

      def self.weighted_majority_vote neighbors
        return [nil,nil] if neighbors.empty?
        weighted_sum = {}
        sim_sum = 0.0
        neighbors.each do |row|
          n,sim,acts = row
          acts.each do |act|
            weighted_sum[act] ||= 0
            weighted_sum[act] += sim
          end
        end
        case weighted_sum.size
        when 1
          return [weighted_sum.keys.first, 1.0]
        when 2
          sim_sum = weighted_sum[weighted_sum.keys[0]]
          sim_sum -= weighted_sum[weighted_sum.keys[1]]
          sim_sum > 0 ? prediction = weighted_sum.keys[0] : prediction = weighted_sum.keys[1] 
          confidence = (sim_sum/neighbors.size).abs 
          return [prediction,confidence]
        else
          bad_request_error "Cannot predict more than 2 classes, multinomial classifications is not yet implemented. Received classes were: '#{weighted.sum.keys}'"
        end
      end

      # Classification with majority vote from neighbors weighted by similarity
      # @param [Hash] params Keys `:activities, :sims, :value_map` are required
      # @return [Numeric] A prediction value.
      def self.fminer_weighted_majority_vote neighbors, training_dataset

        neighbor_contribution = 0.0
        confidence_sum = 0.0

        $logger.debug "Weighted Majority Vote Classification."

        values = neighbors.collect{|n| n[2]}.uniq
        neighbors.each do |neighbor|
          i = training_dataset.compound_ids.index n.id
          neighbor_weight = neighbor[1]
          activity = values.index(neighbor[2]) + 1 # map values to integers > 1
          neighbor_contribution += activity * neighbor_weight
          if values.size == 2 # AM: provide compat to binary classification: 1=>false 2=>true
            case activity
            when 1
              confidence_sum -= neighbor_weight
            when 2
              confidence_sum += neighbor_weight
            end
          else
            confidence_sum += neighbor_weight
          end
        end
        if values.size == 2 
          if confidence_sum >= 0.0
            prediction = values[1]
          elsif confidence_sum < 0.0
            prediction = values[0] 
          end
        elsif values.size == 1 # all neighbors have the same value
          prediction = values[0] 
        else 
          prediction = (neighbor_contribution/confidence_sum).round  # AM: new multinomial prediction
        end 

        confidence = (confidence_sum/neighbors.size).abs 
        {:value => prediction, :confidence => confidence.abs}
      end

      # Local support vector regression from neighbors 
      # @param [Hash] params Keys `:props, :activities, :sims, :min_train_performance` are required
      # @return [Numeric] A prediction value.
      def self.local_svm_classification(params)

        confidence = 0.0
        prediction = nil

        $logger.debug "Local SVM."
        if params[:activities].size>0
          if params[:props]
            n_prop = params[:props][0].collect.to_a
            q_prop = params[:props][1].collect.to_a
            props = [ n_prop, q_prop ]
          end
          activities = params[:activities].collect.to_a
          activities = activities.collect{|v| "Val" + v.to_s} # Convert to string for R to recognize classification
          prediction = local_svm_prop( props, activities, params[:min_train_performance]) # params[:props].nil? signals non-prop setting
          prediction = prediction.sub(/Val/,"") if prediction # Convert back
          confidence = 0.0 if prediction.nil?
          #$logger.debug "Prediction: '" + prediction.to_s + "' ('#{prediction.class}')."
          confidence = get_confidence({:sims => params[:sims][1], :activities => params[:activities]})
        end
        {:prediction => prediction, :confidence => confidence}

      end



    end

  end
end

