module OpenTox

  class LeaveOneOutValidation

    field :model_id, type: BSON::ObjectId
    field :dataset_id, type: BSON::ObjectId
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :predictions, type: Array
    field :finished_at, type: Time 

    def self.create model
      model.training_dataset.features.first.nominal? ? klass = ClassificationLeaveOneOutValidation : klass = RegressionLeaveOneOutValidation
      loo = klass.new :model_id => model.id, :dataset_id => model.training_dataset_id
      compound_ids = model.training_dataset.compound_ids
      predictions = model.predict model.training_dataset.compounds
      predictions = predictions.each_with_index {|p,i| p[:compound_id] = compound_ids[i]}
      predictions.select!{|p| p[:database_activities] and !p[:database_activities].empty?}
      loo.nr_instances = predictions.size
      predictions.select!{|p| p[:value]} # remove unpredicted
      loo.predictions = predictions#.sort{|a,b| b[:confidence] <=> a[:confidence]}
      loo.nr_unpredicted = loo.nr_instances - loo.predictions.size
      loo.statistics
      loo.save
      loo
    end

    def model
      Model::Lazar.find model_id
    end
  end

  class ClassificationLeaveOneOutValidation < LeaveOneOutValidation

    field :accept_values, type: Array
    field :confusion_matrix, type: Array, default: []
    field :weighted_confusion_matrix, type: Array, default: []
    field :accuracy, type: Float
    field :weighted_accuracy, type: Float
    field :true_rate, type: Hash, default: {}
    field :predictivity, type: Hash, default: {}
    field :confidence_plot_id, type: BSON::ObjectId

    def statistics
      accept_values = Feature.find(model.prediction_feature_id).accept_values
      confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      weighted_confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      predictions.each do |pred|
        pred[:database_activities].each do |db_act|
          if pred[:value]
            if pred[:value] == db_act
              if pred[:value] == accept_values[0]
                confusion_matrix[0][0] += 1
                weighted_confusion_matrix[0][0] += pred[:confidence]
              elsif pred[:value] == accept_values[1]
                confusion_matrix[1][1] += 1
                weighted_confusion_matrix[1][1] += pred[:confidence]
              end
            else
              if pred[:value] == accept_values[0]
                confusion_matrix[0][1] += 1
                weighted_confusion_matrix[0][1] += pred[:confidence]
              elsif pred[:value] == accept_values[1]
                confusion_matrix[1][0] += 1
                weighted_confusion_matrix[1][0] += pred[:confidence]
              end
            end
          end
        end
      end
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
      update_attributes(
        accept_values: accept_values,
        confusion_matrix: confusion_matrix,
        weighted_confusion_matrix: weighted_confusion_matrix,
        accuracy: (confusion_matrix[0][0]+confusion_matrix[1][1])/(nr_instances-nr_unpredicted).to_f,
        weighted_accuracy: (weighted_confusion_matrix[0][0]+weighted_confusion_matrix[1][1])/confidence_sum.to_f,
        true_rate: true_rate,
        predictivity: predictivity,
        finished_at: Time.now
      )
      $logger.debug "Accuracy #{accuracy}"
    end

    def confidence_plot
      unless confidence_plot_id
        tmpfile = "/tmp/#{id.to_s}_confidence.svg"
        accuracies = []
        confidences = []
        correct_predictions = 0
        incorrect_predictions = 0
        predictions.each do |p|
          p[:database_activities].each do |db_act|
            if p[:value] 
              p[:value] == db_act ? correct_predictions += 1 : incorrect_predictions += 1
              accuracies << correct_predictions/(correct_predictions+incorrect_predictions).to_f
              confidences << p[:confidence]

            end
          end
        end
        R.assign "accuracy", accuracies
        R.assign "confidence", confidences
        R.eval "image = qplot(confidence,accuracy)+ylab('accumulated accuracy')+scale_x_reverse()"
        R.eval "ggsave(file='#{tmpfile}', plot=image)"
        file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_confidence_plot.svg")
        plot_id = $gridfs.insert_one(file)
        update(:confidence_plot_id => plot_id)
      end
      $gridfs.find_one(_id: confidence_plot_id).data
    end
  end
  

  class RegressionLeaveOneOutValidation < LeaveOneOutValidation


    field :rmse, type: Float, default: 0.0
    field :mae, type: Float, default: 0
    #field :weighted_rmse, type: Float, default: 0
    #field :weighted_mae, type: Float, default: 0
    field :r_squared, type: Float
    field :correlation_plot_id, type: BSON::ObjectId
    field :confidence_plot_id, type: BSON::ObjectId

    def statistics
      confidence_sum = 0
      predicted_values = []
      measured_values = []
      predictions.each do |pred|
        pred[:database_activities].each do |activity|
          if pred[:value]
            predicted_values << pred[:value]
            measured_values << activity
            error = Math.log10(pred[:value])-Math.log10(activity)
            self.rmse += error**2
            #self.weighted_rmse += pred[:confidence]*error**2
            self.mae += error.abs
            #self.weighted_mae += pred[:confidence]*error.abs
            #confidence_sum += pred[:confidence]
          end
        end
        if pred[:database_activities].empty?
          warnings << "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
          $logger.debug "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
        end
      end
      R.assign "measurement", measured_values
      R.assign "prediction", predicted_values
      R.eval "r <- cor(-log(measurement),-log(prediction),use='complete')"
      r = R.eval("r").to_ruby

      self.mae = self.mae/predictions.size
      #self.weighted_mae = self.weighted_mae/confidence_sum
      self.rmse = Math.sqrt(self.rmse/predictions.size)
      #self.weighted_rmse = Math.sqrt(self.weighted_rmse/confidence_sum)
      self.r_squared = r**2
      self.finished_at = Time.now
      save
      $logger.debug "R^2 #{r**2}"
      $logger.debug "RMSE #{rmse}"
      $logger.debug "MAE #{mae}"
    end

    def correlation_plot
      unless correlation_plot_id
        tmpfile = "/tmp/#{id.to_s}_correlation.svg"
        predicted_values = []
        measured_values = []
        predictions.each do |pred|
          pred[:database_activities].each do |activity|
            if pred[:value]
              predicted_values << pred[:value]
              measured_values << activity
            end
          end
        end
        attributes = Model::Lazar.find(self.model_id).attributes
        attributes.delete_if{|key,_| key.match(/_id|_at/) or ["_id","creator","name"].include? key}
        attributes = attributes.values.collect{|v| v.is_a?(String) ? v.sub(/OpenTox::/,'') : v}.join("\n")
        R.assign "measurement", measured_values
        R.assign "prediction", predicted_values
        R.eval "all = c(-log(measurement),-log(prediction))"
        R.eval "range = c(min(all), max(all))"
        R.eval "image = qplot(-log(prediction),-log(measurement),main='#{self.name}',asp=1,xlim=range, ylim=range)"
        R.eval "image = image + geom_abline(intercept=0, slope=1)"
        R.eval "ggsave(file='#{tmpfile}', plot=image)"
        file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_correlation_plot.svg")
        plot_id = $gridfs.insert_one(file)
        update(:correlation_plot_id => plot_id)
      end
      $gridfs.find_one(_id: correlation_plot_id).data
    end
  end

end
