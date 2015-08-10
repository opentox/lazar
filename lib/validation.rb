module OpenTox

  class Validation

    field :prediction_dataset_id, type: BSON::ObjectId
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

  end

  class ClassificationValidation < Validation
    field :accept_values, type: String
    field :confusion_matrix, type: Array
    field :weighted_confusion_matrix, type: Array

    def self.create model, training_set, test_set
      validation = self.class.new
      #feature_dataset = Dataset.find model.feature_dataset_id
      # TODO check and delegate to Algorithm
      #features = Algorithm.run feature_dataset.training_algorithm, training_set, feature_dataset.training_parameters
      validation_model = model.class.create training_set#, features
      test_set_without_activities = Dataset.new(:compound_ids => test_set.compound_ids) # just to be sure that activities cannot be used
      prediction_dataset = validation_model.predict test_set_without_activities
      accept_values = prediction_dataset.prediction_feature.accept_values
      confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      weighted_confusion_matrix = Array.new(accept_values.size,0){Array.new(accept_values.size,0)}
      predictions = []
      nr_unpredicted = 0
      prediction_dataset.data_entries.each_with_index do |pe,i|
        if pe[0] and pe[1] and pe[1].numeric? 
          prediction = pe[0]
          # TODO prediction_feature, convention??
          # TODO generalize for multiple classes
          activity = test_set.data_entries[i].first
          confidence = prediction_dataset.data_entries[i][1]
          predictions << [prediction_dataset.compound_ids[i], activity, prediction, confidence]
          if prediction == activity
            if prediction == accept_values[0]
              confusion_matrix[0][0] += 1
              weighted_confusion_matrix[0][0] += confidence
            elsif prediction == accept_values[1]
              confusion_matrix[1][1] += 1
              weighted_confusion_matrix[1][1] += confidence
            end
          elsif prediction != activity
            if prediction == accept_values[0]
              confusion_matrix[0][1] += 1
              weighted_confusion_matrix[0][1] += confidence
            elsif prediction == accept_values[1]
              confusion_matrix[1][0] += 1
              weighted_confusion_matrix[1][0] += confidence
            end
          end
        else
          nr_unpredicted += 1 if pe[0].nil?
        end
      end
      validation = self.new(
        :prediction_dataset_id => prediction_dataset.id,
        :test_dataset_id => test_set.id,
        :nr_instances => test_set.compound_ids.size,
        :nr_unpredicted => nr_unpredicted,
        :accept_values => accept_values,
        :confusion_matrix => confusion_matrix,
        :weighted_confusion_matrix => weighted_confusion_matrix,
        :predictions => predictions.sort{|a,b| b[3] <=> a[3]} # sort according to confidence
      )
      validation.save
      validation
    end
  end

  class RegressionValidation < Validation
    def self.create model, training_set, test_set
      
      validation_model = Model::LazarRegression.create training_set
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
        :prediction_dataset_id => prediction_dataset.id,
        :test_dataset_id => test_set.id,
        :nr_instances => test_set.compound_ids.size,
        :nr_unpredicted => nr_unpredicted,
        :predictions => predictions.sort{|a,b| b[3] <=> a[3]} # sort according to confidence
      )
      validation.save
      validation
    end
  end

end
