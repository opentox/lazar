module OpenTox

  module Validation

    class TrainTest < Validation

      field :training_dataset_id, type: BSON::ObjectId
      field :test_dataset_id, type: BSON::ObjectId

      def self.create model, training_set, test_set
        
        atts = model.attributes.dup # do not modify attributes of the original model
        atts["_id"] = BSON::ObjectId.new
        atts[:training_dataset_id] = training_set.id
        validation_model = model.class.create model.prediction_feature, training_set, atts
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

      def test_dataset
        Dataset.find test_dataset_id
      end

      def training_dataset
        Dataset.find training_dataset_id
      end

    end

    class ClassificationTrainTest < TrainTest
      include ClassificationStatistics
    end

    class RegressionTrainTest < TrainTest
      include RegressionStatistics
    end

  end

end
