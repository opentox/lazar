module OpenTox

  module Validation

    class LeaveOneOut < Validation

      def self.create model
        $logger.debug "#{model.name}: LOO validation started"
        t = Time.now
        model.training_dataset.features.first.nominal? ? klass = ClassificationLeaveOneOut : klass = RegressionLeaveOneOut
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

    class ClassificationLeaveOneOut < LeaveOneOut
      include ClassificationStatistics
      field :accept_values, type: Array
      field :confusion_matrix, type: Array, default: []
      field :weighted_confusion_matrix, type: Array, default: []
      field :accuracy, type: Float
      field :weighted_accuracy, type: Float
      field :true_rate, type: Hash, default: {}
      field :predictivity, type: Hash, default: {}
      field :confidence_plot_id, type: BSON::ObjectId
    end
    
    class RegressionLeaveOneOut  < LeaveOneOut
      include RegressionStatistics
      field :rmse, type: Float, default: 0
      field :mae, type: Float, default: 0
      field :r_squared, type: Float
      field :correlation_plot_id, type: BSON::ObjectId
      field :confidence_plot_id, type: BSON::ObjectId
    end

  end

end
