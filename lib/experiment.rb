module OpenTox

  class Experiment
    field :dataset_ids, type: Array
    field :model_settings, type: Array
    field :results, type: Hash, default: {}
  end

  def run 
    dataset_ids.each do |dataset_id|
      dataset = Dataset.find(dataset_id)
      results[dataset_id.to_s] = []
      model_settings.each do |setting|
        model = Object.const_get(setting[:algorithm]).create dataset
        model.prediction_algorithm = setting[:prediction_algorithm] if setting[:prediction_algorithm]
        model.neighbor_algorithm = setting[:neighbor_algorithm] if setting[:neighbor_algorithm]
        model.neighbor_algorithm_parameters = setting[:neighbor_algorithm_parameter] if setting[:neighbor_algorithm_parameter]
        model.save
        repeated_crossvalidation = RepeatedCrossValidation.create model
        results[dataset_id.to_s] << {:model_id => model.id, :repeated_crossvalidation_id => repeated_crossvalidation.id}
      end
    end
    save
  end

  def self.create params
    experiment = self.new
    $logge.debug "Experiment started ..."
    experiment.run params
    experiment
  end

  def report
    # TODO significances
    report = {}
    report[:name] = name
    report[:experiment_id] = self.id.to_s
    dataset_ids.each do |dataset_id|
      dataset_name = Dataset.find(dataset_id).name
      report[dataset_name] = []
      results[dataset_id.to_s].each do |result|
        model = Model::Lazar.find(result[:model_id])
        repeated_cv = RepeatedCrossValidation.find(result[:repeated_crossvalidation_id])
        crossvalidations = repeated_cv.crossvalidations
        summary = {}
        [:neighbor_algorithm, :neighbor_algorithm_parameters, :prediction_algorithm].each do |key|
          summary[key] = model[key]
        end
        summary[:nr_instances] = crossvalidations.first.nr_instances
        summary[:nr_unpredicted] = crossvalidations.collect{|cv| cv.nr_unpredicted}
        summary[:time] = crossvalidations.collect{|cv| cv.time}
        if crossvalidations.first.is_a? ClassificationCrossValidation
          summary[:accuracies] = crossvalidations.collect{|cv| cv.accuracy}
        elsif crossvalidations.first.is_a? RegressionCrossValidation
          summary[:r_squared] = crossvalidations.collect{|cv| cv.r_squared}
        end
        report[dataset_name] << summary
        #p repeated_cv.crossvalidations.collect{|cv| cv.accuracy}
        #file = "/tmp/#{id}.svg"
        #File.open(file,"w+"){|f| f.puts cv.correlation_plot}
        #`inkview '#{file}'`
      end
    end
    report
  end

end
