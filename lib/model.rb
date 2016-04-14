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

        # TODO document convention
        #p training_dataset.features
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

      def predict_compound compound
        prediction_feature = Feature.find prediction_feature_id
        neighbors = compound.send(neighbor_algorithm, neighbor_algorithm_parameters)
        # remove neighbors without prediction_feature
        # check for database activities (neighbors may include query compound)
        database_activities = nil
        prediction = {}
        if neighbors.collect{|n| n["_id"]}.include? compound.id

          #TODO restrict to dataset features
          database_activities = neighbors.select{|n| n["_id"] == compound.id}.first["toxicities"][prediction_feature.id.to_s].uniq
          prediction[:database_activities] = database_activities
          prediction[:warning] = "#{database_activities.size} compounds have been removed from neighbors, because they have the same structure as the query compound."
          neighbors.delete_if{|n| n["_id"] == compound.id}
        end
        neighbors.delete_if{|n| n['toxicities'].empty? or n['toxicities'][prediction_feature.id.to_s] == [nil] }
        if neighbors.empty?
          prediction.merge!({:value => nil,:confidence => nil,:warning => "Could not find similar compounds with experimental data in the training dataset.",:neighbors => []})
        else
          prediction.merge!(Algorithm.run(prediction_algorithm, compound, {:neighbors => neighbors,:training_dataset_id=> training_dataset_id,:prediction_feature_id => prediction_feature.id}))
          prediction[:neighbors] = neighbors
          prediction[:neighbors] ||= []
        end
        prediction
      end

      def predict object

        training_dataset = Dataset.find training_dataset_id

        # parse data
        compounds = []
        if object.is_a? Substance
          compounds = [object] 
        elsif object.is_a? Array
          compounds = object
        elsif object.is_a? Dataset
          compounds = object.compounds
        else 
          bad_request_error "Please provide a OpenTox::Compound an Array of OpenTox::Compounds or an OpenTox::Dataset as parameter."
        end

        # make predictions
        predictions = {}
        compounds.each do |c|
          predictions[c.id.to_s] = predict_compound c
          predictions[c.id.to_s][:prediction_feature_id] = prediction_feature_id 
        end

        # serialize result
        if object.is_a? Substance
          prediction = predictions[compounds.first.id.to_s]
          prediction[:neighbors].sort!{|a,b| b[1] <=> a[1]} # sort according to similarity
          return prediction
        elsif object.is_a? Array
          return predictions
        elsif object.is_a? Dataset
          predictions.each{|cid,p| p.delete(:neighbors)}
          # prepare prediction dataset
          measurement_feature = Feature.find prediction_feature_id

          prediction_feature = NumericFeature.find_or_create_by( "name" => measurement_feature.name + " (Prediction)" )
          prediction_dataset = LazarPrediction.create(
            :name => "Lazar prediction for #{prediction_feature.name}",
            :creator =>  __FILE__,
            :prediction_feature_id => prediction_feature.id,
            :predictions => predictions
          )

          #prediction_dataset.save
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
        model.prediction_algorithm ||= "OpenTox::Algorithm::Regression.local_fingerprint_regression" 
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

    class NanoLazar
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
      field :training_particle_ids, type: Array

      def self.create_all
        nanoparticles = Nanoparticle.all
        toxfeatures = Nanoparticle.all.collect{|np| np.toxicities.keys}.flatten.uniq.collect{|id| Feature.find id}
        tox = {}
        toxfeatures.each do |t|
          tox[t] = nanoparticles.select{|np| np.toxicities.keys.include? t.id.to_s}
        end
        tox.select!{|t,nps| nps.size > 50}
        tox.collect do |t,nps|
          find_or_create_by(:prediction_feature_id => t.id, :training_particle_ids => nps.collect{|np| np.id})
        end
      end

      def predict nanoparticle
        training = training_particle_ids.collect{|id| Nanoparticle.find id}
        training_features = training.collect{|t| t.physchem_descriptors.keys}.flatten.uniq
        query_features = nanoparticle.physchem_descriptors.keys
        common_features = (training_features & query_features)
        #p common_features
      end

    end

  end

end
