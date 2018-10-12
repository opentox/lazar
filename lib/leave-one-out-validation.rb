module OpenTox

  module Validation

    # Leave one out validation
    class LeaveOneOut < Validation

      # Create a leave one out validation
      # @param [OpenTox::Model::Lazar]
      # @return [OpenTox::Validation::LeaveOneOut]
      def self.create model
        bad_request_error "Cannot create leave one out validation for models with supervised feature selection. Please use crossvalidation instead." if model.algorithms[:feature_selection]
        $logger.debug "#{model.name}: LOO validation started"
        t = Time.now
        model.training_dataset.features.collect{|f| f.class}.include?(NominalBioActivity) ? klass = ClassificationLeaveOneOut : klass = RegressionLeaveOneOut
        loo = klass.new :model_id => model.id
        predictions = model.predict model.training_dataset.substances
        predictions.each{|cid,p| p.delete(:neighbors)}
        nr_unpredicted = 0
        predictions.each do |cid,prediction|
          if prediction[:value]
            prediction[:measurements] = model.training_dataset.values(cid, prediction[:prediction_feature_id])
          else
            nr_unpredicted += 1
          end
          predictions.delete(cid) unless prediction[:value] and prediction[:measurements]
        end
        predictions.select!{|cid,p| p[:value] and p[:measurements]}
        loo.nr_instances = predictions.size
        loo.nr_unpredicted = nr_unpredicted
        loo.predictions = predictions
        loo.statistics
        $logger.debug "#{model.name}, LOO validation:  #{Time.now-t} seconds"
        loo
      end

    end

    # Leave one out validation for classification models
    class ClassificationLeaveOneOut < LeaveOneOut
      include ClassificationStatistics
      field :accept_values, type: Array
      field :confusion_matrix, type: Hash
      field :weighted_confusion_matrix, type: Hash
      field :accuracy, type: Hash
      field :weighted_accuracy, type: Hash
      field :true_rate, type: Hash
      field :predictivity, type: Hash
      field :nr_predictions, type: Hash
      field :probability_plot_id, type: BSON::ObjectId
    end
    
    # Leave one out validation for regression models
    class RegressionLeaveOneOut  < LeaveOneOut
      include RegressionStatistics
      field :rmse, type: Hash
      field :mae, type: Hash
      field :r_squared, type: Hash
      field :within_prediction_interval, type: Hash
      field :out_of_prediction_interval, type: Hash
      field :nr_predictions, type: Hash
      field :warnings, type: Array
      field :correlation_plot_id, type: BSON::ObjectId
    end

  end

end
