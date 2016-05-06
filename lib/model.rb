module OpenTox

  module Model

    class Lazar 
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "models"

      field :name, type: String
      field :creator, type: String, default: __FILE__
      field :training_dataset_id, type: BSON::ObjectId
      field :prediction_algorithm, type: String
      field :prediction_feature_id, type: BSON::ObjectId
      field :neighbor_algorithm, type: String
      field :neighbor_algorithm_parameters, type: Hash, default: {}
      field :feature_selection_algorithm, type: String
      field :relevant_features, type: Hash

      # Create a lazar model from a training_dataset and a feature_dataset
      # @param [OpenTox::Dataset] training_dataset
      # @return [OpenTox::Model::Lazar] Regression or classification model
      def initialize prediction_feature, training_dataset, params={}

        super params

        # set defaults for empty parameters
        self.prediction_feature_id ||= prediction_feature.id
        self.training_dataset_id ||= training_dataset.id
        self.name ||= "#{training_dataset.name} #{prediction_feature.name}" 
        self.neighbor_algorithm_parameters ||= {}
        self.neighbor_algorithm_parameters[:training_dataset_id] = training_dataset.id

        Algorithm.run(feature_selection_algorithm, self) if feature_selection_algorithm
        save
        self
      end

      def correlation_filter
        toxicities = []
        substances = []
        training_dataset.substances.each do |s|
          s["toxicities"][prediction_feature_id].each do |act|
            toxicities << act
            substances << s
          end
        end
        R.assign "tox", toxicities
        feature_ids = training_dataset.substances.collect{ |s| s["physchem_descriptors"].keys}.flatten.uniq
        feature_ids.each do |feature_id|
          feature_values = substances.collect{|s| s["physchem_descriptors"][feature_id]}
          R.assign "feature", feature_values
          begin
            #R.eval "cor <- cor.test(-log(tox),-log(feature),use='complete')"
            R.eval "cor <- cor.test(tox,feature,method = 'pearson',use='complete')"
            pvalue = R.eval("cor$p.value").to_ruby
            if pvalue <= 0.05
              r = R.eval("cor$estimate").to_ruby
              relevant_features[feature] = {}
              relevant_features[feature]["pvalue"] = pvalue
              relevant_features[feature]["r"] = r
            end
          rescue
            warn "Correlation of '#{Feature.find(feature_id).name}' (#{feature_values}) with '#{Feature.find(prediction_feature_id).name}' (#{toxicities}) failed."
          end
        end
        relevant_features.sort!{|a,b| a[1]["pvalue"] <=> b[1]["pvalue"]}.to_h
      end

      def predict_compound compound
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

      def training_dataset
        Dataset.find(training_dataset_id)
      end

      def prediction_feature
        Feature.find(prediction_feature_id)
      end

    end

    class LazarClassification < Lazar
      
      def self.create prediction_feature, training_dataset, params={}
        model = self.new prediction_feature, training_dataset, params
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

      def self.create prediction_feature, training_dataset, params={}
        model = self.new prediction_feature, training_dataset, params
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

      field :endpoint, type: String
      field :species, type: String
      field :source, type: String
      field :unit, type: String
      field :model_id, type: BSON::ObjectId
      field :repeated_crossvalidation_id, type: BSON::ObjectId
      field :leave_one_out_validation_id, type: BSON::ObjectId

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

      def leave_one_out_validation
        LeaveOneOutValidation.find leave_one_out_validation_id
      end

      def regression?
        model.is_a? LazarRegression
      end

      def classification?
        model.is_a? LazarClassification
      end

      def self.from_csv_file file
        metadata_file = file.sub(/csv$/,"json")
        bad_request_error "No metadata file #{metadata_file}" unless File.exist? metadata_file
        prediction_model = self.new JSON.parse(File.read(metadata_file))
        training_dataset = Dataset.from_csv_file file
        prediction_feature = training_dataset.features.first
        model = nil
        if prediction_feature.nominal?
          model = LazarClassification.create prediction_feature, training_dataset
        elsif prediction_feature.numeric?
          model = LazarRegression.create prediction_feature, training_dataset
        end
        prediction_model[:model_id] = model.id
        prediction_model[:prediction_feature_id] = prediction_feature.id
        prediction_model[:repeated_crossvalidation_id] = RepeatedCrossValidation.create(model).id
        prediction_model[:leave_one_out_validation_id] = LeaveOneOutValidation.create(model).id
        prediction_model.save
        prediction_model
      end
    end

  end

end
