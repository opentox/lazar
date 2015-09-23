module OpenTox

  class Validation

    field :model_id, type: BSON::ObjectId
    field :prediction_dataset_id, type: BSON::ObjectId
    field :crossvalidation_id, type: BSON::ObjectId
    field :test_dataset_id, type: BSON::ObjectId
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :predictions, type: Array

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
      
      atts = model.attributes.dup # do not modify attributes from original model
      atts["_id"] = BSON::ObjectId.new
      atts[:training_dataset_id] = training_set.id
      validation_model = model.class.create training_set, atts
      validation_model.save
      test_set_without_activities = Dataset.new(:compound_ids => test_set.compound_ids) # just to be sure that activities cannot be used
      prediction_dataset = validation_model.predict test_set_without_activities
      predictions = []
      nr_unpredicted = 0
      activities = test_set.data_entries.collect{|de| de.first}
      prediction_dataset.data_entries.each_with_index do |de,i|
        if de[0] and de[1] and de[1].numeric? 
          activity = activities[i]
          prediction = de.first
          confidence = de[1]
          predictions << [prediction_dataset.compound_ids[i], activity, prediction,confidence]
        else
          nr_unpredicted += 1
        end
      end
      validation = self.new(
        :model_id => validation_model.id,
        :prediction_dataset_id => prediction_dataset.id,
        :test_dataset_id => test_set.id,
        :nr_instances => test_set.compound_ids.size,
        :nr_unpredicted => nr_unpredicted,
        :predictions => predictions.sort{|a,b| b[3] <=> a[3]} # sort according to confidence
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
