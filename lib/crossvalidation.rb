module OpenTox

  class CrossValidation
    field :validation_ids, type: Array, default: []
    field :folds, type: Integer
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :predictions, type: Array
    field :finished_at, type: Time 
  end

  class ClassificationCrossValidation < CrossValidation

    field :accept_values, type: Array
    field :confusion_matrix, type: Array
    field :weighted_confusion_matrix, type: Array
    field :accuracy, type: Float
    field :weighted_accuracy, type: Float
    field :true_rate, type: Hash
    field :predictivity, type: Hash
    # TODO auc, f-measure (usability??)

    def self.create model, n=10
      cv = self.new
      validation_ids = []
      nr_instances = 0
      nr_unpredicted = 0
      predictions = []
      validation_class = Object.const_get(self.to_s.sub(/Cross/,''))
      accept_values = Feature.find(model.prediction_feature_id).accept_values
      confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      weighted_confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      true_rate = {}
      predictivity = {}
      fold_nr = 1
      training_dataset = Dataset.find model.training_dataset_id
      training_dataset.folds(n).each do |fold|
        t = Time.now
        $logger.debug "Fold #{fold_nr}"
        validation = validation_class.create(model, fold[0], fold[1])
        validation_ids << validation.id
        nr_instances += validation.nr_instances
        nr_unpredicted += validation.nr_unpredicted
        predictions += validation.predictions
        validation.confusion_matrix.each_with_index do |r,i|
          r.each_with_index do |c,j|
            confusion_matrix[i][j] += c
            weighted_confusion_matrix[i][j] += validation.weighted_confusion_matrix[i][j]
          end
        end
        $logger.debug "Fold #{fold_nr}:  #{Time.now-t} seconds"
        fold_nr +=1
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
      cv.update_attributes(
        nr_instances: nr_instances,
        nr_unpredicted: nr_unpredicted,
        accept_values: accept_values,
        confusion_matrix: confusion_matrix,
        weighted_confusion_matrix: weighted_confusion_matrix,
        accuracy: (confusion_matrix[0][0]+confusion_matrix[1][1])/(nr_instances-nr_unpredicted).to_f,
        weighted_accuracy: (weighted_confusion_matrix[0][0]+weighted_confusion_matrix[1][1])/confidence_sum.to_f,
        true_rate: true_rate,
        predictivity: predictivity,
        predictions: predictions.sort{|a,b| b[3] <=> a[3]}, # sort according to confidence
        finished_at: Time.now
      )
      cv.save
      cv
    end

    #Average area under roc  0.646
    #Area under roc  0.646
    #F measure carcinogen: 0.769, noncarcinogen: 0.348
  end

  class RegressionCrossValidation < Validation

    field :validation_ids, type: Array, default: []
    field :folds, type: Integer
    field :rmse, type: Float
    field :mae, type: Float
    field :weighted_rmse, type: Float
    field :weighted_mae, type: Float

    def self.create model, n=10
      cv = self.new
      validation_ids = []
      nr_instances = 0
      nr_unpredicted = 0
      predictions = []
      validation_class = Object.const_get(self.to_s.sub(/Cross/,''))
      fold_nr = 1
      training_dataset = Dataset.find model.training_dataset_id
      training_dataset.folds(n).each do |fold|
        t = Time.now
        $logger.debug "Predicting fold #{fold_nr}"

        validation = validation_class.create(model, fold[0], fold[1])
        validation_ids << validation.id
        nr_instances += validation.nr_instances
        nr_unpredicted += validation.nr_unpredicted
        predictions += validation.predictions
        $logger.debug "Fold #{fold_nr}:  #{Time.now-t} seconds"
        fold_nr +=1
      end
      rmse = 0
      weighted_rmse = 0
      rse = 0
      weighted_rse = 0
      mae = 0
      weighted_mae = 0
      rae = 0
      weighted_rae = 0
      n = 0
      confidence_sum = 0
      predictions.each do |pred|
        compound_id,activity,prediction,confidence = pred
        if activity and prediction
          error = prediction-activity
          rmse += error**2
          weighted_rmse += confidence*error**2
          mae += error.abs
          weighted_mae += confidence*error.abs
          n += 1
          confidence_sum += confidence
        else
          # TODO: create warnings
          p pred
        end
      end
      mae = mae/n
      weighted_mae = weighted_mae/confidence_sum
      rmse = Math.sqrt(rmse/n)
      weighted_rmse = Math.sqrt(weighted_rmse/confidence_sum)
      cv.update_attributes(
        folds: n,
        validation_ids: validation_ids,
        nr_instances: nr_instances,
        nr_unpredicted: nr_unpredicted,
        predictions: predictions.sort{|a,b| b[3] <=> a[3]},
        mae: mae,
        rmse: rmse,
        weighted_mae: weighted_mae,
        weighted_rmse: weighted_rmse
      )
      cv.save
      cv
    end

    def plot
      # RMSE
      x = predictions.collect{|p| p[1]}
      y = predictions.collect{|p| p[2]}
      R.assign "Measurement", x
      R.assign "Prediction", y
      R.eval "par(pty='s')" # sets the plot type to be square
      #R.eval "fitline <- lm(log(Prediction) ~ log(Measurement))"
      #R.eval "error <- log(Measurement)-log(Prediction)"
      R.eval "error <- Measurement-Prediction"
      R.eval "rmse <- sqrt(mean(error^2,na.rm=T))"
      R.eval "mae <- mean( abs(error), na.rm = TRUE)"
      R.eval "r <- cor(log(Prediction),log(Measurement))"
      R.eval "svg(filename='/tmp/#{id.to_s}.svg')"
      R.eval "plot(log(Prediction),log(Measurement),main='#{self.name}', sub=paste('RMSE: ',rmse, 'MAE :',mae, 'r^2: ',r^2),asp=1)"
      #R.eval "plot(log(Prediction),log(Measurement),main='#{self.name}', sub=paste('RMSE: ',rmse, 'MAE :',mae, 'r^2: '),asp=1)"
      #R.eval "plot(log(Prediction),log(Measurement),main='#{self.name}', ,asp=1)"
      R.eval "abline(0,1,col='blue')"
      #R.eval "abline(fitline,col='red')"
      R.eval "dev.off()"
      "/tmp/#{id.to_s}.svg"
    end
  end


end
