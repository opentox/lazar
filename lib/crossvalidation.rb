module OpenTox

  class CrossValidation
    field :validation_ids, type: Array, default: []
    field :model_id, type: BSON::ObjectId
    field :folds, type: Integer
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :predictions, type: Array, default: []
    field :finished_at, type: Time 

    def time
      finished_at - created_at
    end

    def validations
      validation_ids.collect{|vid| Validation.find vid}
    end

    def model
      Model::Lazar.find model_id
    end

    def self.create model, n=10
      model.training_dataset.features.first.nominal? ? klass = ClassificationCrossValidation : klass = RegressionCrossValidation
      bad_request_error "#{dataset.features.first} is neither nominal nor numeric." unless klass
      cv = klass.new(
        name: model.name,
        model_id: model.id,
        folds: n
      )
      cv.save # set created_at
      nr_instances = 0
      nr_unpredicted = 0
      predictions = []
      training_dataset = Dataset.find model.training_dataset_id
      training_dataset.folds(n).each_with_index do |fold,fold_nr|
        fork do # parallel execution of validations
          $logger.debug "Dataset #{training_dataset.name}: Fold #{fold_nr} started"
          t = Time.now
          validation = Validation.create(model, fold[0], fold[1],cv)
          $logger.debug "Dataset #{training_dataset.name}, Fold #{fold_nr}:  #{Time.now-t} seconds"
        end
      end
      Process.waitall
      cv.validation_ids = Validation.where(:crossvalidation_id => cv.id).distinct(:_id)
      cv.validations.each do |validation|
        nr_instances += validation.nr_instances
        nr_unpredicted += validation.nr_unpredicted
        predictions += validation.predictions
      end
      cv.update_attributes(
        nr_instances: nr_instances,
        nr_unpredicted: nr_unpredicted,
        predictions: predictions.sort{|a,b| b[3] <=> a[3]} # sort according to confidence
      )
      $logger.debug "Nr unpredicted: #{nr_unpredicted}"
      cv.statistics
      cv
    end
  end

  class ClassificationCrossValidation < CrossValidation

    field :accept_values, type: Array
    field :confusion_matrix, type: Array
    field :weighted_confusion_matrix, type: Array
    field :accuracy, type: Float
    field :weighted_accuracy, type: Float
    field :true_rate, type: Hash
    field :predictivity, type: Hash
    field :confidence_plot_id, type: BSON::ObjectId
    # TODO auc, f-measure (usability??)

    def statistics
      accept_values = Feature.find(model.prediction_feature_id).accept_values
      confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      weighted_confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      true_rate = {}
      predictivity = {}
      predictions.each do |pred|
        compound_id,activity,prediction,confidence = pred
        if activity and prediction and confidence.numeric? 
          if prediction == activity
            if prediction == accept_values[0]
              confusion_matrix[0][0] += 1
              weighted_confusion_matrix[0][0] += confidence
            elsif prediction == accept_values[1]
              confusion_matrix[1][1] += 1
              weighted_confusion_matrix[1][1] += confidence
            end
          elsif prediction != activity
            if prediction == accept_values[0]
              confusion_matrix[0][1] += 1
              weighted_confusion_matrix[0][1] += confidence
            elsif prediction == accept_values[1]
              confusion_matrix[1][0] += 1
              weighted_confusion_matrix[1][0] += confidence
            end
          end
        else
          nr_unpredicted += 1 if prediction.nil?
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
          if p[1] and p[2]
            p[1] == p[2] ? correct_predictions += 1 : incorrect_predictions += 1
            accuracies << correct_predictions/(correct_predictions+incorrect_predictions).to_f
            confidences << p[3]

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

    #Average area under roc  0.646
    #Area under roc  0.646
    #F measure carcinogen: 0.769, noncarcinogen: 0.348
  end

  class RegressionCrossValidation < CrossValidation

    field :rmse, type: Float
    field :mae, type: Float
    field :weighted_rmse, type: Float
    field :weighted_mae, type: Float
    field :r_squared, type: Float
    field :correlation_plot_id, type: BSON::ObjectId
    field :confidence_plot_id, type: BSON::ObjectId

    def statistics
      rmse = 0
      weighted_rmse = 0
      rse = 0
      weighted_rse = 0
      mae = 0
      weighted_mae = 0
      rae = 0
      weighted_rae = 0
      confidence_sum = 0
      predictions.each do |pred|
        compound_id,activity,prediction,confidence = pred
        if activity and prediction
          error = Math.log10(prediction)-Math.log10(activity)
          rmse += error**2
          weighted_rmse += confidence*error**2
          mae += error.abs
          weighted_mae += confidence*error.abs
          confidence_sum += confidence
        else
          warnings << "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
          $logger.debug "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
        end
      end
      x = predictions.collect{|p| p[1]}
      y = predictions.collect{|p| p[2]}
      R.assign "measurement", x
      R.assign "prediction", y
      R.eval "r <- cor(-log(measurement),-log(prediction),use='complete')"
      r = R.eval("r").to_ruby

      mae = mae/predictions.size
      weighted_mae = weighted_mae/confidence_sum
      rmse = Math.sqrt(rmse/predictions.size)
      weighted_rmse = Math.sqrt(weighted_rmse/confidence_sum)
      update_attributes(
        mae: mae,
        rmse: rmse,
        weighted_mae: weighted_mae,
        weighted_rmse: weighted_rmse,
        r_squared: r**2,
        finished_at: Time.now
      )
      $logger.debug "R^2 #{r**2}"
      $logger.debug "RMSE #{rmse}"
      $logger.debug "MAE #{mae}"
    end

    def misclassifications n=nil
      #n = predictions.size unless n
      n ||= 10 
      model = Model::Lazar.find(self.model_id)
      training_dataset = Dataset.find(model.training_dataset_id)
      prediction_feature = training_dataset.features.first
      predictions.collect do |p|
        unless p.include? nil
          compound = Compound.find(p[0])
          neighbors = compound.send(model.neighbor_algorithm,model.neighbor_algorithm_parameters)
          neighbors.collect! do |n|
            neighbor = Compound.find(n[0])
            values = training_dataset.values(neighbor,prediction_feature)
            { :smiles => neighbor.smiles, :similarity => n[1], :measurements => values}
          end
          {
            :smiles => compound.smiles, 
            #:fingerprint => compound.fp4.collect{|id|  Smarts.find(id).name},
            :measured => p[1],
            :predicted => p[2],
            #:relative_error => (Math.log10(p[1])-Math.log10(p[2])).abs/Math.log10(p[1]).to_f.abs,
            :log_error => (Math.log10(p[1])-Math.log10(p[2])).abs,
            :relative_error => (p[1]-p[2]).abs/p[1],
            :confidence => p[3],
            :neighbors => neighbors
          }
        end
      end.compact.sort{|a,b| b[:relative_error] <=> a[:relative_error]}[0..n-1]
    end

    def confidence_plot
      tmpfile = "/tmp/#{id.to_s}_confidence.svg"
      sorted_predictions = predictions.collect{|p| [(Math.log10(p[1])-Math.log10(p[2])).abs,p[3]] if p[1] and p[2]}.compact
      R.assign "error", sorted_predictions.collect{|p| p[0]}
      R.assign "confidence", sorted_predictions.collect{|p| p[1]}
      # TODO fix axis names
      R.eval "image = qplot(confidence,error)"
      R.eval "image = image + stat_smooth(method='lm', se=FALSE)"
      R.eval "ggsave(file='#{tmpfile}', plot=image)"
      file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_confidence_plot.svg")
      plot_id = $gridfs.insert_one(file)
      update(:confidence_plot_id => plot_id)
      $gridfs.find_one(_id: confidence_plot_id).data
    end

    def correlation_plot
      unless correlation_plot_id
        tmpfile = "/tmp/#{id.to_s}_correlation.svg"
        x = predictions.collect{|p| p[1]}
        y = predictions.collect{|p| p[2]}
        attributes = Model::Lazar.find(self.model_id).attributes
        attributes.delete_if{|key,_| key.match(/_id|_at/) or ["_id","creator","name"].include? key}
        attributes = attributes.values.collect{|v| v.is_a?(String) ? v.sub(/OpenTox::/,'') : v}.join("\n")
        R.assign "measurement", x
        R.assign "prediction", y
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

  class RepeatedCrossValidation
    field :crossvalidation_ids, type: Array, default: []
    def self.create model, folds=10, repeats=3
      repeated_cross_validation = self.new
      repeats.times do |n|
        $logger.debug "Crossvalidation #{n+1} for #{model.name}"
        repeated_cross_validation.crossvalidation_ids << CrossValidation.create(model, folds).id
      end
      repeated_cross_validation.save
      repeated_cross_validation
    end
    def crossvalidations
      crossvalidation_ids.collect{|id| CrossValidation.find(id)}
    end
  end


end
