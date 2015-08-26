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
      cv.save # set created_at
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
        #validation_ids << validation.id
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
        name: model.name,
        model_id: model.id,
        folds: n,
        #validation_ids: validation_ids,
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

  class RegressionCrossValidation < CrossValidation

    field :rmse, type: Float
    field :mae, type: Float
    field :weighted_rmse, type: Float
    field :weighted_mae, type: Float
    field :weighted_mae, type: Float
    field :r_squared, type: Float
    field :correlation_plot_id, type: BSON::ObjectId

    def self.create model, n=10
      cv = self.new
      cv.save # set created_at
      #validation_ids = []
      nr_instances = 0
      nr_unpredicted = 0
      predictions = []
      validation_class = Object.const_get(self.to_s.sub(/Cross/,''))
      fold_nr = 1
      training_dataset = Dataset.find model.training_dataset_id
      training_dataset.folds(n).each_with_index do |fold,fold_nr|
        fork do # parallel execution of validations
          $logger.debug "Dataset #{training_dataset.name}: Fold #{fold_nr} started"
          t = Time.now
          validation = validation_class.create(model, fold[0], fold[1],cv)
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
      rmse = 0
      weighted_rmse = 0
      rse = 0
      weighted_rse = 0
      mae = 0
      weighted_mae = 0
      rae = 0
      weighted_rae = 0
      confidence_sum = 0
      #nil_activities = []
      predictions.each do |pred|
        compound_id,activity,prediction,confidence = pred
        if activity and prediction
          error = Math.log(prediction)-Math.log(activity)
          rmse += error**2
          weighted_rmse += confidence*error**2
          mae += error.abs
          weighted_mae += confidence*error.abs
          confidence_sum += confidence
          cv.predictions << pred
        else
          # TODO: create warnings
          cv.warnings << "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{training_dataset.id}."
          $logger.debug "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{training_dataset.id}."
          #nil_activities << pred
        end
      end
      #predictions -= nil_activities
      x = cv.predictions.collect{|p| p[1]}
      y = cv.predictions.collect{|p| p[2]}
      R.assign "measurement", x
      R.assign "prediction", y
      R.eval "r <- cor(-log(measurement),-log(prediction))"
      r = R.eval("r").to_ruby

      mae = mae/cv.predictions.size
      weighted_mae = weighted_mae/confidence_sum
      rmse = Math.sqrt(rmse/cv.predictions.size)
      weighted_rmse = Math.sqrt(weighted_rmse/confidence_sum)
      # TODO check!!
      cv.predictions.sort! do |a,b|
        relative_error_a = (a[1]-a[2]).abs/a[1].to_f
        relative_error_a = 1/relative_error_a if relative_error_a < 1
        relative_error_b = (b[1]-b[2]).abs/b[1].to_f
        relative_error_b = 1/relative_error_b if relative_error_b < 1
        [relative_error_b,b[3]] <=> [relative_error_a,a[3]]
      end
      cv.update_attributes(
        name: model.name,
        model_id: model.id,
        folds: n,
        #validation_ids: validation_ids,
        nr_instances: nr_instances,
        nr_unpredicted: nr_unpredicted,
        #predictions: predictions,#.sort{|a,b| [(b[1]-b[2]).abs/b[1].to_f,b[3]] <=> [(a[1]-a[2]).abs/a[1].to_f,a[3]]},
        mae: mae,
        rmse: rmse,
        weighted_mae: weighted_mae,
        weighted_rmse: weighted_rmse,
        r_squared: r**2
      )
      cv.save
      cv
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

    def correlation_plot
      unless correlation_plot_id
        tmpfile = "/tmp/#{id.to_s}.svg"
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


end
