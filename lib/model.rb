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
      field :neighbor_algorithm_parameters, type: Hash

      #attr_accessor :prediction_dataset
      #attr_accessor :training_dataset

      # Create a lazar model from a training_dataset and a feature_dataset
      # @param [OpenTox::Dataset] training_dataset
      # @return [OpenTox::Model::Lazar] Regression or classification model
      def self.create training_dataset

        bad_request_error "More than one prediction feature found in training_dataset #{training_dataset.id}" unless training_dataset.features.size == 1

        # TODO document convention
        prediction_feature = training_dataset.features.first
        prediction_feature.nominal ?  lazar = OpenTox::Model::LazarClassification.new : lazar = OpenTox::Model::LazarRegression.new
        lazar.training_dataset_id = training_dataset.id
        lazar.prediction_feature_id = prediction_feature.id
        lazar.name = "#{training_dataset.name} #{prediction_feature.name}" 

        lazar.save
        lazar
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
          database_activities = training_dataset.values(compound,prediction_feature)
          if database_activities and !database_activities.empty?
            database_activities = database_activities.first if database_activities.size == 1
            predictions << {:compound => compound, :value => database_activities, :confidence => "measured", :warning => "Compound #{compound.smiles} occurs in training dataset with activity '#{database_activities}'."}
            next
          end
          neighbors = Algorithm.run(neighbor_algorithm, compound, neighbor_algorithm_parameters)
          # add activities
          # TODO: improve efficiency, takes 3 times longer than previous version
          neighbors.collect! do |n|
            rows = training_dataset.compound_ids.each_index.select{|i| training_dataset.compound_ids[i] == n.first}
            acts = rows.collect{|row| training_dataset.data_entries[row][0]}.compact
            acts.empty? ? nil : n << acts
          end
          neighbors.compact! # remove neighbors without training activities
          predictions << Algorithm.run(prediction_algorithm, compound, {:neighbors => neighbors,:training_dataset_size => training_dataset.data_entries.size})
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
          prediction_dataset = LazarPrediction.new(
            :name => "Lazar prediction for #{prediction_feature.name}",
            :creator =>  __FILE__,
            :prediction_feature_id => prediction_feature.id

          )
          confidence_feature = OpenTox::NumericFeature.find_or_create_by( "name" => "Prediction confidence" )
          # TODO move into warnings field
          warning_feature = OpenTox::NominalFeature.find_or_create_by("name" => "Warnings")
          prediction_dataset.features = [ prediction_feature, confidence_feature, warning_feature ]
          prediction_dataset.compounds = compounds
          prediction_dataset.data_entries = predictions.collect{|p| [p[:value], p[:confidence], p[:warning]]}
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
      def initialize
        super
        self.prediction_algorithm = "OpenTox::Algorithm::Classification.weighted_majority_vote"
        self.neighbor_algorithm = "OpenTox::Algorithm::Neighbor.fingerprint_similarity"
        self.neighbor_algorithm_parameters = {:min_sim => 0.7}
      end
    end

    class LazarFminerClassification < LazarClassification
      field :feature_calculation_parameters, type: Hash

      def self.create training_dataset, fminer_params={}
        model = super(training_dataset)
        model.update "_type" => self.to_s # adjust class
        model = self.find model.id # adjust class
        model.neighbor_algorithm = "OpenTox::Algorithm::Neighbor.fminer_similarity"
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

    class LazarRegression < Lazar
      def initialize
        super
        self.neighbor_algorithm = "OpenTox::Algorithm::Neighbor.fingerprint_similarity"
        self.prediction_algorithm = "OpenTox::Algorithm::Regression.weighted_average" 
        self.neighbor_algorithm_parameters = {:min_sim => 0.7}
      end
    end

    class Prediction
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps

      # TODO field Validations
      field :endpoint, type: String
      field :species, type: String
      field :source, type: String
      field :unit, type: String
      field :model_id, type: BSON::ObjectId
      field :crossvalidation_id, type: BSON::ObjectId

      def predict object
        Lazar.find(model_id).predict object
      end

      def training_dataset
        model.training_dataset
      end

      def model
        Lazar.find model_id
      end

      def crossvalidation
        CrossValidation.find crossvalidation_id
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
        cv = nil
        if training_dataset.features.first.nominal?
          model = LazarFminerClassification.create training_dataset
          cv = ClassificationCrossValidation.create model
        elsif training_dataset.features.first.numeric?
          model = LazarRegression.create training_dataset
          cv = RegressionCrossValidation.create model
        end
        prediction_model[:model_id] = model.id
        prediction_model[:crossvalidation_id] = cv.id
        prediction_model.save
        prediction_model
      end
    end

  end

end
