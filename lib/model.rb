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
        self.neighbor_algorithm_parameters[:dataset_id] = training_dataset.id

        #send(feature_selection_algorithm.to_sym) if feature_selection_algorithm
        save
      end

      def correlation_filter
        self.relevant_features = {}
        measurements = []
        substances = []
        training_dataset.substances.each do |s|
          training_dataset.values(s,prediction_feature_id).each do |act|
            measurements << act
            substances << s
          end
        end
        R.assign "tox", measurements
        feature_ids = training_dataset.substances.collect{ |s| s["physchem_descriptors"].keys}.flatten.uniq
        feature_ids.each do |feature_id|
          feature_values = substances.collect{|s| s["physchem_descriptors"][feature_id].first if s["physchem_descriptors"][feature_id]}
          R.assign "feature", feature_values
          begin
            R.eval "cor <- cor.test(tox,feature,method = 'pearson',use='pairwise')"
            pvalue = R.eval("cor$p.value").to_ruby
            if pvalue <= 0.05
              r = R.eval("cor$estimate").to_ruby
              self.relevant_features[feature_id] = {}
              self.relevant_features[feature_id]["pvalue"] = pvalue
              self.relevant_features[feature_id]["r"] = r
            end
          rescue
            warn "Correlation of '#{Feature.find(feature_id).name}' (#{feature_values}) with '#{Feature.find(prediction_feature_id).name}' (#{measurements}) failed."
          end
        end
        self.relevant_features = self.relevant_features.sort{|a,b| a[1]["pvalue"] <=> b[1]["pvalue"]}.to_h
      end

      def predict_substance substance
        neighbor_algorithm_parameters = Hash[self.neighbor_algorithm_parameters.map{ |k, v| [k.to_sym, v] }] # convert string keys to symbols
        neighbors = substance.send(neighbor_algorithm, neighbor_algorithm_parameters)
        measurements = nil
        prediction = {}
        # handle query substance
        if neighbors.collect{|n| n["_id"]}.include? substance.id

          query = neighbors.select{|n| n["_id"] == substance.id}.first
          measurements = training_dataset.values(query["_id"],prediction_feature_id)
          prediction[:measurements] = measurements
          prediction[:warning] = "#{measurements.size} substances have been removed from neighbors, because they are identical with the query substance."
          neighbors.delete_if{|n| n["_id"] == substance.id} # remove query substance for an unbiased prediction (also useful for loo validation)
        end
        if neighbors.empty?
          prediction.merge!({:value => nil,:probabilities => nil,:warning => "Could not find similar substances with experimental data in the training dataset.",:neighbors => []})
        elsif neighbors.size == 1
          value = nil
          tox = neighbors.first["measurements"]
          if tox.size == 1 # single measurement
            value = tox.first
          else # multiple measurement
            if tox.collect{|t| t.numeric?}.uniq == [true] # numeric
              value = tox.median
            elsif tox.uniq.size == 1 # single value
              value = tox.first
            else # contradictory results
              # TODO add majority vote??
            end
          end
          prediction.merge!({:value => value, :probabilities => nil, :warning => "Only one similar compound in the training set. Predicting median of its experimental values.", :neighbors => neighbors}) if value
        else
          # call prediction algorithm
          klass,method = prediction_algorithm.split('.')
          result = Object.const_get(klass).send(method,substance,neighbors)
          prediction.merge! result
          prediction[:neighbors] = neighbors
          prediction[:neighbors] ||= []
        end
        prediction
      end

      def predict object

        training_dataset = Dataset.find training_dataset_id

        # parse data
        substances = []
        if object.is_a? Substance
          substances = [object] 
        elsif object.is_a? Array
          substances = object
        elsif object.is_a? Dataset
          substances = object.substances
        else 
          bad_request_error "Please provide a OpenTox::Compound an Array of OpenTox::Compounds or an OpenTox::Dataset as parameter."
        end

        # make predictions
        predictions = {}
        substances.each do |c|
          predictions[c.id.to_s] = predict_substance c
          predictions[c.id.to_s][:prediction_feature_id] = prediction_feature_id 
        end

        # serialize result
        if object.is_a? Substance
          prediction = predictions[substances.first.id.to_s]
          prediction[:neighbors].sort!{|a,b| b[1] <=> a[1]} # sort according to similarity
          return prediction
        elsif object.is_a? Array
          return predictions
        elsif object.is_a? Dataset
          #predictions.each{|cid,p| p.delete(:neighbors)}
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
          :dataset_id => training_dataset.id,
          :prediction_feature_id => prediction_feature.id,
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
          :min_sim => 0.1,
          :dataset_id => training_dataset.id,
          :prediction_feature_id => prediction_feature.id,
        }.each do |key,value|
          model.neighbor_algorithm_parameters[key] ||= value
        end
        model.neighbor_algorithm_parameters[:type] ||= "MP2D" if training_dataset.substances.first.is_a? Compound
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
        Validation::RepeatedCrossValidation.find repeated_crossvalidation_id
      end

      def crossvalidations
        repeated_crossvalidation.crossvalidations
      end

      def leave_one_out_validation
        Validation::LeaveOneOut.find leave_one_out_validation_id
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
        prediction_model[:repeated_crossvalidation_id] = Validation::RepeatedCrossValidation.create(model).id
        prediction_model[:leave_one_out_validation_id] = Validation::LeaveOneOut.create(model).id
        prediction_model.save
        prediction_model
      end
    end

  end

end
