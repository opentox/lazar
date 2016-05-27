module OpenTox

  class LeaveOneOutValidation

    field :model_id, type: BSON::ObjectId
    field :nr_instances, type: Integer
    field :nr_unpredicted, type: Integer
    field :predictions, type: Hash
    field :finished_at, type: Time 

    def self.create model
      $logger.debug "#{model.name}: LOO validation started"
      t = Time.now
      model.training_dataset.features.first.nominal? ? klass = ClassificationLeaveOneOutValidation : klass = RegressionLeaveOneOutValidation
      loo = klass.new :model_id => model.id
      predictions = model.predict model.training_dataset.substances
      predictions.each{|cid,p| p.delete(:neighbors)}
      nr_unpredicted = 0
      predictions.each do |cid,prediction|
        if prediction[:value]
          prediction[:measured] = model.training_dataset.values(cid, prediction[:prediction_feature_id])
        else
          nr_unpredicted += 1
        end
        predictions.delete(cid) unless prediction[:value] and prediction[:measured]
      end
      predictions.select!{|cid,p| p[:value] and p[:measured]}
      loo.nr_instances = predictions.size
      loo.nr_unpredicted = nr_unpredicted
      loo.predictions = predictions
      loo.statistics
      loo.save
      $logger.debug "#{model.name}, LOO validation:  #{Time.now-t} seconds"
      loo
    end

    def model
      Model::Lazar.find model_id
    end
  end

  class ClassificationLeaveOneOutValidation < LeaveOneOutValidation

    field :accept_values, type: Array
    field :confusion_matrix, type: Array, default: []
    field :weighted_confusion_matrix, type: Array, default: []
    field :accuracy, type: Float
    field :weighted_accuracy, type: Float
    field :true_rate, type: Hash, default: {}
    field :predictivity, type: Hash, default: {}
    field :confidence_plot_id, type: BSON::ObjectId

    def statistics
      stat = ValidationStatistics.classification(predictions, Feature.find(model.prediction_feature_id).accept_values)
      update_attributes(stat)
    end

    def confidence_plot
      unless confidence_plot_id
        tmpfile = "/tmp/#{id.to_s}_confidence.svg"
        accuracies = []
        confidences = []
        correct_predictions = 0
        incorrect_predictions = 0
        predictions.each do |p|
          p[:database_activities].each do |db_act|
            if p[:value] 
              p[:value] == db_act ? correct_predictions += 1 : incorrect_predictions += 1
              accuracies << correct_predictions/(correct_predictions+incorrect_predictions).to_f
              confidences << p[:confidence]

            end
          end
        end
        R.assign "accuracy", accuracies
        R.assign "confidence", confidences
        R.eval "image = qplot(confidence,accuracy)+ylab('accumulated accuracy')+scale_x_reverse()"
        R.eval "ggsave(file='#{tmpfile}', plot=image)"
        file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_confidence_plot.svg")
        plot_id = $gridfs.insert_one(file)
        update(:confidence_plot_id => plot_id)
      end
      $gridfs.find_one(_id: confidence_plot_id).data
    end
  end
  

  class RegressionLeaveOneOutValidation < LeaveOneOutValidation

    field :rmse, type: Float, default: 0
    field :mae, type: Float, default: 0
    field :r_squared, type: Float
    field :correlation_plot_id, type: BSON::ObjectId
    field :confidence_plot_id, type: BSON::ObjectId

    def statistics
      stat = ValidationStatistics.regression predictions
      update_attributes(stat)
    end

    def correlation_plot
      unless correlation_plot_id
        plot_id = ValidationStatistics.correlation_plot id, predictions
        update(:correlation_plot_id => plot_id)
      end
      $gridfs.find_one(_id: correlation_plot_id).data
    end
  end

end
