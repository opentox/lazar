module OpenTox

  module Validation
    class CrossValidation < Validation
      field :validation_ids, type: Array, default: []
      field :folds, type: Integer, default: 10

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
        #predictions = {}
        training_dataset = Dataset.find model.training_dataset_id
        training_dataset.folds(n).each_with_index do |fold,fold_nr|
          #fork do # parallel execution of validations can lead to Rserve and memory problems
            $logger.debug "Dataset #{training_dataset.name}: Fold #{fold_nr} started"
            t = Time.now
            validation = TrainTest.create(model, fold[0], fold[1])
            cv.validation_ids << validation.id
            cv.nr_instances += validation.nr_instances
            cv.nr_unpredicted += validation.nr_unpredicted
            #cv.predictions.merge! validation.predictions
            $logger.debug "Dataset #{training_dataset.name}, Fold #{fold_nr}:  #{Time.now-t} seconds"
          #end
        end
        #Process.waitall
        cv.save
        $logger.debug "Nr unpredicted: #{nr_unpredicted}"
        cv.statistics
        cv.update_attributes(finished_at: Time.now)
        cv
      end

      def time
        finished_at - created_at
      end

      def validations
        validation_ids.collect{|vid| TrainTest.find vid}
      end

      def predictions
        predictions = {}
        validations.each{|v| predictions.merge!(v.predictions)}
        predictions
      end
    end

    class ClassificationCrossValidation < CrossValidation
      include ClassificationStatistics
      field :accept_values, type: Array
      field :confusion_matrix, type: Array
      field :weighted_confusion_matrix, type: Array
      field :accuracy, type: Float
      field :weighted_accuracy, type: Float
      field :true_rate, type: Hash
      field :predictivity, type: Hash
      field :confidence_plot_id, type: BSON::ObjectId
    end

    class RegressionCrossValidation < CrossValidation
      include RegressionStatistics
      field :rmse, type: Float
      field :mae, type: Float
      field :r_squared, type: Float
      field :correlation_plot_id, type: BSON::ObjectId
    end

    class RepeatedCrossValidation < Validation
      field :crossvalidation_ids, type: Array, default: []
      field :correlation_plot_id, type: BSON::ObjectId

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

      def correlation_plot format: "png"
        #unless correlation_plot_id
          feature = Feature.find(crossvalidations.first.model.prediction_feature)
          title = feature.name
          title += "[#{feature.unit}]" if feature.unit and !feature.unit.blank?
          tmpfile = "/tmp/#{id.to_s}_correlation.#{format}"
          images = []
          crossvalidations.each_with_index do |cv,i|
            x = []
            y = []
            cv.predictions.each do |sid,p|
              x << p["value"]
              y << p["measurements"].median
            end
            R.assign "measurement", x
            R.assign "prediction", y
            R.eval "all = c(measurement,prediction)"
            R.eval "range = c(min(all), max(all))"
            R.eval "image#{i} = qplot(prediction,measurement,main='#{title}',xlab='Prediction',ylab='Measurement',asp=1,xlim=range, ylim=range)"
            R.eval "image#{i} = image#{i} + geom_abline(intercept=0, slope=1)"
            images << "image#{i}"
          end
          R.eval "pdf('#{tmpfile}')"
          R.eval "grid.arrange(#{images.join ","},ncol=#{images.size})"
          R.eval "dev.off()"
          file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{id.to_s}_correlation_plot.#{format}")
          correlation_plot_id = $gridfs.insert_one(file)
          update(:correlation_plot_id => correlation_plot_id)
        #end
      $gridfs.find_one(_id: correlation_plot_id).data
      end
    end
  end

end
