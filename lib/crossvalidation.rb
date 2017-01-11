module OpenTox

  module Validation

    # Crossvalidation
    class CrossValidation < Validation
      field :validation_ids, type: Array, default: []
      field :folds, type: Integer, default: 10

      # Create a crossvalidation
      # @param [OpenTox::Model::Lazar]
      # @param [Fixnum] number of folds
      # @return [OpenTox::Validation::CrossValidation]
      def self.create model, n=10
        $logger.debug model.algorithms
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
        training_dataset = model.training_dataset
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

      # Get execution time
      # @return [Fixnum]
      def time
        finished_at - created_at
      end

      # Get individual validations
      # @return [Array<OpenTox::Validation>]
      def validations
        validation_ids.collect{|vid| TrainTest.find vid}
      end

      # Get predictions for all compounds
      # @return [Array<Hash>]
      def predictions
        predictions = {}
        validations.each{|v| predictions.merge!(v.predictions)}
        predictions
      end
    end

    # Crossvalidation of classification models
    class ClassificationCrossValidation < CrossValidation
      include ClassificationStatistics
      field :accept_values, type: Array
      field :confusion_matrix, type: Array
      field :weighted_confusion_matrix, type: Array
      field :accuracy, type: Float
      field :weighted_accuracy, type: Float
      field :true_rate, type: Hash
      field :predictivity, type: Hash
      field :probability_plot_id, type: BSON::ObjectId
    end

    # Crossvalidation of regression models
    class RegressionCrossValidation < CrossValidation
      include RegressionStatistics
      field :rmse, type: Float, default:0
      field :mae, type: Float, default:0
      field :r_squared, type: Float
      field :within_prediction_interval, type: Integer, default:0
      field :out_of_prediction_interval, type: Integer, default:0
      field :correlation_plot_id, type: BSON::ObjectId
    end

    # Independent repeated crossvalidations
    class RepeatedCrossValidation < Validation
      field :crossvalidation_ids, type: Array, default: []
      field :correlation_plot_id, type: BSON::ObjectId

      # Create repeated crossvalidations
      # @param [OpenTox::Model::Lazar]
      # @param [Fixnum] number of folds
      # @param [Fixnum] number of repeats
      # @return [OpenTox::Validation::RepeatedCrossValidation]
      def self.create model, folds=10, repeats=3
        repeated_cross_validation = self.new
        repeats.times do |n|
          $logger.debug "Crossvalidation #{n+1} for #{model.name}"
          repeated_cross_validation.crossvalidation_ids << CrossValidation.create(model, folds).id
        end
        repeated_cross_validation.save
        repeated_cross_validation
      end

      # Get crossvalidations
      # @return [OpenTox::Validation::CrossValidation]
      def crossvalidations
        crossvalidation_ids.collect{|id| CrossValidation.find(id)}
      end

    end
  end

end
