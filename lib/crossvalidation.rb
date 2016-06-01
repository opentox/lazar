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
        predictions = {}
        training_dataset = Dataset.find model.training_dataset_id
        training_dataset.folds(n).each_with_index do |fold,fold_nr|
          #fork do # parallel execution of validations can lead to Rserve and memory problems
            $logger.debug "Dataset #{training_dataset.name}: Fold #{fold_nr} started"
            t = Time.now
            validation = TrainTest.create(model, fold[0], fold[1])
            cv.validation_ids << validation.id
            cv.nr_instances += validation.nr_instances
            cv.nr_unpredicted += validation.nr_unpredicted
            cv.predictions.merge! validation.predictions
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

end
