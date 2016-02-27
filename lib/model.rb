module OpenTox

  module Model

    class Model
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "models"

      field :name, type: String
      field :creator, type: String, default: __FILE__
      # datasets
      field :training_dataset_id, type: BSON::ObjectId
      # algorithms
      field :prediction_algorithm, type: String
      # prediction feature
      field :prediction_feature_id, type: BSON::ObjectId

      def training_dataset
        Dataset.find(training_dataset_id)
      end
    end

    class Lazar < Model

      # algorithms
      field :neighbor_algorithm, type: String
      field :neighbor_algorithm_parameters, type: Hash, default: {}

      # Create a lazar model from a training_dataset and a feature_dataset
      # @param [OpenTox::Dataset] training_dataset
      # @return [OpenTox::Model::Lazar] Regression or classification model
      def initialize training_dataset, params={}

        super params
        #bad_request_error "More than one prediction feature found in training_dataset #{training_dataset.id}" unless training_dataset.features.size == 1

        # TODO document convention
        prediction_feature = training_dataset.features.first
        # set defaults for empty parameters
        self.prediction_feature_id ||= prediction_feature.id
        self.training_dataset_id ||= training_dataset.id
        self.name ||= "#{training_dataset.name} #{prediction_feature.name}" 
        self.neighbor_algorithm_parameters ||= {}
        self.neighbor_algorithm_parameters[:training_dataset_id] = training_dataset.id
        save
        self
      end

      def predict object

        t = Time.now
        at = Time.now

        training_dataset = Dataset.find training_dataset_id
        prediction_feature = Feature.find prediction_feature_id

        # parse data
        compounds = []
        case object.class.to_s
        when "OpenTox::Compound"
          compounds = [object] 
        when "Array"
          compounds = object
        when "OpenTox::Dataset"
          compounds = object.compounds
        else 
          bad_request_error "Please provide a OpenTox::Compound an Array of OpenTox::Compounds or an OpenTox::Dataset as parameter."
        end

        # make predictions
        predictions = []
        neighbors = []
        compounds.each_with_index do |compound,c|
          t = Time.new

          neighbors = compound.send(neighbor_algorithm, neighbor_algorithm_parameters)
          # remove neighbors without prediction_feature
          # check for database activities (neighbors may include query compound)
          database_activities = nil
          prediction = {}
          if neighbors.collect{|n| n["_id"]}.include? compound.id

            database_activities = neighbors.select{|n| n["_id"] == compound.id}.first["features"][prediction_feature.id.to_s]
            prediction[:database_activities] = database_activities
            prediction[:warning] = "#{database_activities.size} structures have been removed from neighbors, because they have the same structure as the query compound."
            neighbors.delete_if{|n| n["_id"] == compound.id}
          end
          neighbors.delete_if{|n| n['features'].empty? or n['features'][prediction_feature.id.to_s] == [nil] }
          if neighbors.empty?
            prediction.merge!({:value => nil,:confidence => nil,:warning => "Could not find similar compounds with experimental data in the training dataset."})
          else
            prediction.merge!(Algorithm.run(prediction_algorithm, compound, {:neighbors => neighbors,:training_dataset_id=> training_dataset.id,:prediction_feature_id => prediction_feature.id}))
          end
          predictions << prediction
        end 

        # serialize result
        case object.class.to_s
        when "OpenTox::Compound"
          prediction = predictions.first
          prediction[:neighbors] = neighbors.sort{|a,b| b[1] <=> a[1]} # sort according to similarity
          return prediction
        when "Array"
          return predictions
        when "OpenTox::Dataset"
          # prepare prediction dataset
          measurement_feature = prediction_feature
          prediction_feature = OpenTox::NumericFeature.find_or_create_by( "name" => measurement_feature.name + " (Prediction)" )
          prediction_dataset = LazarPrediction.new(
            :name => "Lazar prediction for #{prediction_feature.name}",
            :creator =>  __FILE__,
            :prediction_feature_id => prediction_feature.id

          )
          confidence_feature = OpenTox::NumericFeature.find_or_create_by( "name" => "Prediction confidence" )
          # TODO move into warnings field
          warning_feature = OpenTox::NominalFeature.find_or_create_by("name" => "Warnings")
          prediction_dataset.features = [ prediction_feature, confidence_feature, measurement_feature, warning_feature ]
          prediction_dataset.compounds = compounds
          #prediction_dataset.data_entries = predictions.collect{|p| [p[:value], p[:database_activities] ? "measured" : p[:confidence] , p[:warning]]}
          # TODO fix dataset measurements
          prediction_dataset.data_entries = predictions.collect{|p| [p[:value], p[:confidence] , p[:dataset_activities].to_s, p[:warning]]}
          prediction_dataset.save_all
          return prediction_dataset
        end

      end
      
      def training_activities
        i = training_dataset.feature_ids.index prediction_feature_id
        training_dataset.data_entries.collect{|de| de[i]}
      end

    end

    class LazarClassification < Lazar
      
      def self.create training_dataset, params={}
        model = self.new training_dataset, params
        model.prediction_algorithm = "OpenTox::Algorithm::Classification.weighted_majority_vote" unless model.prediction_algorithm
        model.neighbor_algorithm ||= "fingerprint_neighbors"
        model.neighbor_algorithm_parameters ||= {}
        {
          :type => "MP2D",
          :training_dataset_id => training_dataset.id,
          :min_sim => 0.1
        }.each do |key,value|
          model.neighbor_algorithm_parameters[key] ||= value
        end
        model.save
        model
      end
    end

    class LazarRegression < Lazar

      def self.create training_dataset, params={}
        model = self.new training_dataset, params
        model.neighbor_algorithm ||= "fingerprint_neighbors"
        model.prediction_algorithm ||= "OpenTox::Algorithm::Regression.local_pls_regression" 
        model.neighbor_algorithm_parameters ||= {}
        {
          :type => "MP2D",
          :training_dataset_id => training_dataset.id,
          :min_sim => 0.1
          #:type => "FP4",
          #:training_dataset_id => training_dataset.id,
          #:min_sim => 0.7
        }.each do |key,value|
          model.neighbor_algorithm_parameters[key] ||= value
        end
        model.save
        model
      end
    end

    class LazarFminerClassification < LazarClassification
      field :feature_calculation_parameters, type: Hash

      def self.create training_dataset, fminer_params={}
        model = super(training_dataset)
        model.update "_type" => self.to_s # adjust class
        model = self.find model.id # adjust class
        model.neighbor_algorithm = "fminer_neighbors"
        model.neighbor_algorithm_parameters = {
          :feature_calculation_algorithm => "OpenTox::Algorithm::Descriptor.smarts_match",
          :feature_dataset_id => Algorithm::Fminer.bbrc(training_dataset,fminer_params).id,
          :min_sim => 0.3
        }
        model.feature_calculation_parameters = fminer_params
        model.save
        model
      end
    end

    class Prediction
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps

      # TODO cv -> repeated cv
      # TODO field Validations
      field :endpoint, type: String
      field :species, type: String
      field :source, type: String
      field :unit, type: String
      field :model_id, type: BSON::ObjectId
      field :repeated_crossvalidation_id, type: BSON::ObjectId

      def predict object
        Lazar.find(model_id).predict object
      end

      def training_dataset
        model.training_dataset
      end

      def model
        Lazar.find model_id
      end

      def repeated_crossvalidation
        RepeatedCrossValidation.find repeated_crossvalidation_id
      end

      def crossvalidations
        repeated_crossvalidation.crossvalidations
      end

      def regression?
        training_dataset.features.first.numeric?
      end

      def classification?
        training_dataset.features.first.nominal?
      end

      def self.from_csv_file file
        metadata_file = file.sub(/csv$/,"json")
        bad_request_error "No metadata file #{metadata_file}" unless File.exist? metadata_file
        prediction_model = self.new JSON.parse(File.read(metadata_file))
        training_dataset = Dataset.from_csv_file file
        model = nil
        if training_dataset.features.first.nominal?
          #model = LazarFminerClassification.create training_dataset
          model = LazarClassification.create training_dataset
        elsif training_dataset.features.first.numeric?
          model = LazarRegression.create training_dataset
        end
        prediction_model[:model_id] = model.id
        prediction_model[:repeated_crossvalidation_id] = RepeatedCrossValidation.create(model).id
        prediction_model.save
        prediction_model
      end
    end

  end

end
