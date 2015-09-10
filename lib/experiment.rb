module OpenTox

  class Experiment
    field :dataset_ids, type: Array
    field :model_algorithms, type: Array
    field :model_ids, type: Array, default: []
    field :crossvalidation_ids, type: Array, default: []
    field :prediction_algorithms, type: Array
    field :neighbor_algorithms, type: Array
    field :neighbor_algorithm_parameters, type: Array
  end

  # TODO more sophisticated experimental design
  def run 
    dataset_ids.each do |dataset_id|
      dataset = Dataset.find(dataset_id)
      model_algorithms.each do |model_algorithm|
        prediction_algorithms.each do |prediction_algorithm|
          neighbor_algorithms.each do |neighbor_algorithm|
            neighbor_algorithm_parameters.each do |neighbor_algorithm_parameter|
              $logger.debug "Creating #{model_algorithm} model for dataset #{dataset.name}, with prediction_algorithm #{prediction_algorithm}, neighbor_algorithm #{neighbor_algorithm}, neighbor_algorithm_parameters #{neighbor_algorithm_parameter}."
              model = Object.const_get(model_algorithm).create dataset
              model.prediction_algorithm = prediction_algorithm
              model.neighbor_algorithm = neighbor_algorithm
              model.neighbor_algorithm_parameters = neighbor_algorithm_parameter
              model.save
              model_ids << model.id
              cv = nil
              if dataset.features.first.nominal
                cv = ClassificationCrossValidation
              elsif dataset.features.first.numeric
                cv = RegressionCrossValidation
              end
              if cv
                $logger.debug "Creating #{cv} for #{model_algorithm}, dataset #{dataset.name}, with prediction_algorithm #{prediction_algorithm}, neighbor_algorithm #{neighbor_algorithm}, neighbor_algorithm_parameters #{neighbor_algorithm_parameter}."
                crossvalidation = cv.create model
                self.crossvalidation_ids << crossvalidation.id
              else
                $logger.warn "#{dataset.features.first} is neither nominal nor numeric."
              end
            end
          end
        end
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
    # TODO create ggplot2 report
    self.crossvalidation_ids.each do |id|
      cv = CrossValidation.find(id)
      file = "/tmp/#{id}.svg"
      File.open(file,"w+"){|f| f.puts cv.correlation_plot}
      `inkview '#{file}'`
    end
  end

end
