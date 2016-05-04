module OpenTox
  class ValidationStatistics
    include OpenTox
    def self.classification predictions, accept_values
      confusion_matrix = Array.new(accept_values.size){Array.new(accept_values.size,0)}
      weighted_confusion_matrix = Array.new(accept_values.size){Array.new(accept_values.size,0)}
      true_rate = {}
      predictivity = {}
      nr_instances = 0
      predictions.each do |cid,pred|
        # TODO use measured majority class
        if pred[:measured].uniq.size == 1
          m = pred[:measured].first
        #pred[:measured].each do |m|
          if pred[:value] == m
            if pred[:value] == accept_values[0]
              confusion_matrix[0][0] += 1
              weighted_confusion_matrix[0][0] += pred[:probabilities][pred[:value]]
              nr_instances += 1
            elsif pred[:value] == accept_values[1]
              confusion_matrix[1][1] += 1
              weighted_confusion_matrix[1][1] += pred[:probabilities][pred[:value]]
              nr_instances += 1
            end
          elsif pred[:value] != m
            if pred[:value] == accept_values[0]
              confusion_matrix[0][1] += 1
              weighted_confusion_matrix[0][1] += pred[:probabilities][pred[:value]]
              nr_instances += 1
            elsif pred[:value] == accept_values[1]
              confusion_matrix[1][0] += 1
              weighted_confusion_matrix[1][0] += pred[:probabilities][pred[:value]]
              nr_instances += 1
            end
          end
        end
      end
      true_rate = {}
      predictivity = {}
      accept_values.each_with_index do |v,i|
        true_rate[v] = confusion_matrix[i][i]/confusion_matrix[i].reduce(:+).to_f
        predictivity[v] = confusion_matrix[i][i]/confusion_matrix.collect{|n| n[i]}.reduce(:+).to_f
      end
      confidence_sum = 0
      weighted_confusion_matrix.each do |r|
        r.each do |c|
          confidence_sum += c
        end
      end
      accuracy = (confusion_matrix[0][0]+confusion_matrix[1][1])/nr_instances.to_f
      weighted_accuracy = (weighted_confusion_matrix[0][0]+weighted_confusion_matrix[1][1])/confidence_sum.to_f
      $logger.debug "Accuracy #{accuracy}"
      {
        :accept_values => accept_values,
        :confusion_matrix => confusion_matrix,
        :weighted_confusion_matrix => weighted_confusion_matrix,
        :accuracy => accuracy,
        :weighted_accuracy => weighted_accuracy,
        :true_rate => true_rate,
        :predictivity => predictivity,
        :finished_at => Time.now
      }
    end

    def self.regression predictions
      rmse = 0
      mae = 0
      x = []
      y = []
      predictions.each do |cid,pred|
        if pred[:value] and pred[:measured] #and pred[:measured] != [nil]
          x << pred[:measured].median
          y << pred[:value]
          error = pred[:value]-pred[:measured].median
          rmse += error**2
          mae += error.abs
        else
          warnings << "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
          $logger.debug "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
        end
      end
      R.assign "measurement", x
      R.assign "prediction", y
      R.eval "r <- cor(measurement,prediction,use='complete')"
      r = R.eval("r").to_ruby

      mae = mae/predictions.size
      rmse = Math.sqrt(rmse/predictions.size)
      $logger.debug "R^2 #{r**2}"
      $logger.debug "RMSE #{rmse}"
      $logger.debug "MAE #{mae}"
      {
        :mae => mae,
        :rmse => rmse,
        :r_squared => r**2,
        :finished_at => Time.now
      }
    end
  end
end
