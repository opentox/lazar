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
      cids = test_set.compound_ids

      test_set_without_activities = Dataset.new(:compound_ids => cids.uniq) # remove duplicates and make sure that activities cannot be used
      prediction_dataset = validation_model.predict test_set_without_activities
      predictions = []
      nr_unpredicted = 0
      activities = test_set.data_entries.collect{|de| de.first}
      prediction_dataset.data_entries.each_with_index do |de,i|
        if de[0] and de[1] 
          cid = prediction_dataset.compound_ids[i]
          rows = cids.each_index.select{|r| cids[r] == cid }
          activities = rows.collect{|r| test_set.data_entries[r][0]}
          #activity = activities[i]
          prediction = de.first
          confidence = de[1]
          predictions << [prediction_dataset.compound_ids[i], activities, prediction, de[1]]
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

    def statistics
      rmse = 0
      weighted_rmse = 0
      rse = 0
      weighted_rse = 0
      mae = 0
      weighted_mae = 0
      confidence_sum = 0
      predictions.each do |pred|
        compound_id,activity,prediction,confidence = pred
        if activity and prediction
          error = Math.log10(prediction)-Math.log10(activity.median)
          rmse += error**2
          weighted_rmse += confidence*error**2
          mae += error.abs
          weighted_mae += confidence*error.abs
          confidence_sum += confidence
        else
          warnings << "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
          $logger.debug "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
        end
      end
      x = predictions.collect{|p| p[1].median}
      y = predictions.collect{|p| p[2]}
      R.assign "measurement", x
      R.assign "prediction", y
      R.eval "r <- cor(-log(measurement),-log(prediction),use='complete')"
      r = R.eval("r").to_ruby

      mae = mae/predictions.size
      weighted_mae = weighted_mae/confidence_sum
      rmse = Math.sqrt(rmse/predictions.size)
      weighted_rmse = Math.sqrt(weighted_rmse/confidence_sum)
=begin
      update_attributes(
        mae: mae,
        rmse: rmse,
        weighted_mae: weighted_mae,
        weighted_rmse: weighted_rmse,
        r_squared: r**2,
        finished_at: Time.now
      )
=end
      { "R^2" => r**2, "RMSE" => rmse, "MAE" => mae }
    end
  end

end
