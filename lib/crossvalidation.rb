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
      validation_class = Object.const_get(self.to_s.sub(/Cross/,''))
      training_dataset = Dataset.find model.training_dataset_id
      training_dataset.folds(n).each_with_index do |fold,fold_nr|
        fork do # parallel execution of validations
          $logger.debug "Dataset #{training_dataset.name}: Fold #{fold_nr} started"
          t = Time.now
          #p validation_class#.create(model, fold[0], fold[1],cv)
          validation = validation_class.create(model, fold[0], fold[1],cv)
          #p validation
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
        predictions: predictions
      )
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
      R.eval "r <- cor(-log(measurement),-log(prediction))"
      r = R.eval("r").to_ruby

      mae = mae/predictions.size
      weighted_mae = weighted_mae/confidence_sum
      rmse = Math.sqrt(rmse/predictions.size)
      weighted_rmse = Math.sqrt(weighted_rmse/confidence_sum)
      # TODO check!!
=begin
      predictions.sort! do |a,b|
        relative_error_a = (a[1]-a[2]).abs/a[1].to_f
        relative_error_a = 1/relative_error_a if relative_error_a < 1
        relative_error_b = (b[1]-b[2]).abs/b[1].to_f
        relative_error_b = 1/relative_error_b if relative_error_b < 1
        [relative_error_b,b[3]] <=> [relative_error_a,a[3]]
      end
=end
      update_attributes(
        mae: mae,
        rmse: rmse,
        weighted_mae: weighted_mae,
        weighted_rmse: weighted_rmse,
        r_squared: r**2,
        finished_at: Time.now
      )
    end

    def misclassifications n=nil
      #n = predictions.size unless n
      n = 20 unless n
      model = Model::Lazar.find(self.model_id)
      training_dataset = Dataset.find(model.training_dataset_id)
      prediction_feature = training_dataset.features.first
      predictions[0..n-1].collect do |p|
        compound = Compound.find(p[0])
        neighbors = compound.neighbors.collect do |n|
          neighbor = Compound.find(n[0])
          values = training_dataset.values(neighbor,prediction_feature)
          { :smiles => neighbor.smiles, :fingerprint => neighbor.fp4.collect{|id| Smarts.find(id).name},:similarity => n[1], :measurements => values}
        end
        {
          :smiles => compound.smiles, 
          :fingerprint => compound.fp4.collect{|id|  Smarts.find(id).name},
          :measured => p[1],
          :predicted => p[2],
          :relative_error => (p[1]-p[2]).abs/p[1].to_f,
          :confidence => p[3],
          :neighbors => neighbors
        }
      end
    end

    def confidence_plot
      tmpfile = "/tmp/#{id.to_s}_confidence.svg"
      sorted_predictions = predictions.sort{|a,b| b[3]<=>a[3]}.collect{|p| [(Math.log10(p[1])-Math.log10(p[2]))**2,p[3]]}
      R.assign "error", sorted_predictions.collect{|p| p[0]}
      #R.assign "p", predictions.collect{|p| p[2]}
      R.assign "confidence", predictions.collect{|p| p[2]}
      #R.eval "diff = log(m)-log(p)"
      R.eval "library(ggplot2)"
      R.eval "svg(filename='#{tmpfile}')"
      R.eval "image = qplot(confidence,error)"#,main='#{self.name}',asp=1,xlim=range, ylim=range)"
      R.eval "ggsave(file='#{tmpfile}', plot=image)"
        R.eval "dev.off()"
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
        p "'"+attributes
        R.eval "library(ggplot2)"
        R.eval "library(grid)"
        R.eval "library(gridExtra)"
        R.assign "measurement", x
        R.assign "prediction", y
        #R.eval "error <- log(Measurement)-log(Prediction)"
        #R.eval "rmse <- sqrt(mean(error^2, na.rm=T))"
        #R.eval "mae <- mean(abs(error), na.rm=T)"
        #R.eval "r <- cor(-log(prediction),-log(measurement))"
        R.eval "svg(filename='#{tmpfile}')"
        R.eval "all = c(-log(measurement),-log(prediction))"
        R.eval "range = c(min(all), max(all))"
        R.eval "image = qplot(-log(prediction),-log(measurement),main='#{self.name}',asp=1,xlim=range, ylim=range)"
        R.eval "image = image + geom_abline(intercept=0, slope=1) + stat_smooth(method='lm', se=FALSE)"
        R.eval "text = textGrob(paste('RMSE: ', '#{rmse.round(2)},','MAE:','#{mae.round(2)},','r^2: ','#{r_squared.round(2)}','\n\n','#{attributes}'),just=c('left','top'),check.overlap = T)"
        R.eval "grid.arrange(image, text, ncol=2)"
        R.eval "dev.off()"
        file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_correlation_plot.svg")
        plot_id = $gridfs.insert_one(file)
        update(:correlation_plot_id => plot_id)
      end
      p correlation_plot_id
      $gridfs.find_one(_id: correlation_plot_id).data
    end
  end

  class RepeatedCrossValidation
    field :crossvalidation_ids, type: Array, default: []
    def self.create model, folds=10, repeats=3
      repeated_cross_validation = self.new
      repeats.times do
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
