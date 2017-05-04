module OpenTox

  module Validation

    # Training test set validation
    class TrainTest < Validation

      field :training_dataset_id, type: BSON::ObjectId
      field :test_dataset_id, type: BSON::ObjectId

      # Create a training test set validation
      # @param [OpenTox::Model::Lazar]
      # @param [OpenTox::Dataset] training dataset
      # @param [OpenTox::Dataset] test dataset
      # @return [OpenTox::Validation::TrainTest]
      def self.create model, training_set, test_set
        
        validation_model = model.class.create prediction_feature: model.prediction_feature, training_dataset: training_set, algorithms: model.algorithms
        validation_model.save
        predictions = validation_model.predict test_set.substances
        nr_unpredicted = 0
        predictions.each do |cid,prediction|
          if prediction[:value]
            prediction[:measurements] = test_set.values(cid, prediction[:prediction_feature_id])
          else
            nr_unpredicted += 1
          end
        end
        predictions.select!{|cid,p| p[:value] and p[:measurements]}
        # hack to avoid mongos file size limit error on large datasets
        #predictions.each{|cid,p| p[:neighbors] = []} if model.training_dataset.name.match(/mutagenicity/i)
        validation = self.new(
          :model_id => validation_model.id,
          :test_dataset_id => test_set.id,
          :nr_instances => test_set.substances.size,
          :nr_unpredicted => nr_unpredicted,
          :predictions => predictions
        )
        validation.save
        validation
      end

      # Get test dataset
      # @return [OpenTox::Dataset]
      def test_dataset
        Dataset.find test_dataset_id
      end

      # Get training dataset
      # @return [OpenTox::Dataset]
      def training_dataset
        Dataset.find training_dataset_id
      end

    end

    # Training test set validation for classification models
    class ClassificationTrainTest < TrainTest
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

    # Training test set validation for regression models
    class RegressionTrainTest < TrainTest
      include RegressionStatistics
      field :rmse, type: Float, default:0
      field :mae, type: Float, default:0
      field :r_squared, type: Float
      field :within_prediction_interval, type: Integer, default:0
      field :out_of_prediction_interval, type: Integer, default:0
      field :correlation_plot_id, type: BSON::ObjectId
    end

  end

end
