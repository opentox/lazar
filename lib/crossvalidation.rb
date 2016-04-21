module OpenTox

  class CrossValidation
    field :validation_ids, type: Array, default: []
    field :model_id, type: BSON::ObjectId
    field :folds, type: Integer
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :predictions, type: Hash, default: {}
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
      klass = ClassificationCrossValidation if model.is_a? Model::LazarClassification
      klass = RegressionCrossValidation if model.is_a? Model::LazarRegression
      bad_request_error "Unknown model class #{model.class}." unless klass

      cv = klass.new(
        name: model.name,
        model_id: model.id,
        folds: n
      )
      cv.save # set created_at
      nr_instances = 0
      nr_unpredicted = 0
      predictions = {}
      training_dataset = Dataset.find model.training_dataset_id
      training_dataset.folds(n).each_with_index do |fold,fold_nr|
        #fork do # parallel execution of validations can lead to Rserve and memory problems
          $logger.debug "Dataset #{training_dataset.name}: Fold #{fold_nr} started"
          t = Time.now
          validation = Validation.create(model, fold[0], fold[1],cv)
          $logger.debug "Dataset #{training_dataset.name}, Fold #{fold_nr}:  #{Time.now-t} seconds"
        #end
      end
      Process.waitall
      cv.validation_ids = Validation.where(:crossvalidation_id => cv.id).distinct(:_id)
      cv.validations.each do |validation|
        nr_instances += validation.nr_instances
        nr_unpredicted += validation.nr_unpredicted
        predictions.merge! validation.predictions
      end
      cv.update_attributes(
        nr_instances: nr_instances,
        nr_unpredicted: nr_unpredicted,
        predictions: predictions
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
      stat = ValidationStatistics.classification(predictions, Feature.find(model.prediction_feature_id).accept_values)
      update_attributes(stat)
    end

    def confidence_plot
      unless confidence_plot_id
        tmpfile = "/tmp/#{id.to_s}_confidence.png"
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
        file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_confidence_plot.png")
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
    field :r_squared, type: Float
    field :correlation_plot_id, type: BSON::ObjectId

    def statistics
      stat = ValidationStatistics.regression predictions
      update_attributes(stat)
    end

    def misclassifications n=nil
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
            { :smiles => neighbor.smiles, :similarity => n[1], :measurements => neighbor.toxicities[prediction_feature.id.to_s]}
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
      tmpfile = "/tmp/#{id.to_s}_confidence.png"
      sorted_predictions = predictions.collect{|p| [(Math.log10(p[1])-Math.log10(p[2])).abs,p[3]] if p[1] and p[2]}.compact
      R.assign "error", sorted_predictions.collect{|p| p[0]}
      R.assign "confidence", sorted_predictions.collect{|p| p[1]}
      # TODO fix axis names
      R.eval "image = qplot(confidence,error)"
      R.eval "image = image + stat_smooth(method='lm', se=FALSE)"
      R.eval "ggsave(file='#{tmpfile}', plot=image)"
      file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_confidence_plot.png")
      plot_id = $gridfs.insert_one(file)
      update(:confidence_plot_id => plot_id)
      $gridfs.find_one(_id: confidence_plot_id).data
    end

    def correlation_plot
      unless correlation_plot_id
        tmpfile = "/tmp/#{id.to_s}_correlation.png"
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
        file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_correlation_plot.png")
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
