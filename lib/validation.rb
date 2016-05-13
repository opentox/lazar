module OpenTox

  class Validation

    field :model_id, type: BSON::ObjectId
    field :prediction_dataset_id, type: BSON::ObjectId
    field :crossvalidation_id, type: BSON::ObjectId
    field :test_dataset_id, type: BSON::ObjectId
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :predictions, type: Hash

    def prediction_dataset
      Dataset.find prediction_dataset_id
    end

    def test_dataset
      Dataset.find test_dataset_id
    end

    def model
      Model::Lazar.find model_id
    end

    def self.create model, training_set, test_set, crossvalidation=nil
      
      atts = model.attributes.dup # do not modify attributes of the original model
      atts["_id"] = BSON::ObjectId.new
      atts[:training_dataset_id] = training_set.id
      validation_model = model.class.create model.prediction_feature, training_set, atts
      validation_model.save
      predictions = validation_model.predict test_set.substances
      predictions.each{|cid,p| p.delete(:neighbors)}
      nr_unpredicted = 0
      predictions.each do |cid,prediction|
        if prediction[:value]
          prediction[:measured] = test_set.values(cid, prediction[:prediction_feature_id])
        else
          nr_unpredicted += 1
        end
      end
      predictions.select!{|cid,p| p[:value] and p[:measured]}
      validation = self.new(
        :model_id => validation_model.id,
        :test_dataset_id => test_set.id,
        :nr_instances => test_set.substances.size,
        :nr_unpredicted => nr_unpredicted,
        :predictions => predictions#.sort{|a,b| p a; b[3] <=> a[3]} # sort according to confidence
      )
      validation.crossvalidation_id = crossvalidation.id if crossvalidation
      validation.save
      validation
    end

  end

  class ClassificationValidation < Validation
  end

  class RegressionValidation < Validation
  end

end
