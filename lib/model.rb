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
      field :prediction_feature_id, type: BSON::ObjectId
      field :algorithms, type: Hash
      field :relevant_features, type: Hash
      
      def self.create prediction_feature:nil, training_dataset:nil, algorithms:{}
        bad_request_error "Please provide a prediction_feature and/or a training_dataset." unless prediction_feature or training_dataset
        prediction_feature = training_dataset.features.first unless prediction_feature
        # TODO: prediction_feature without training_dataset: use all available data
        # explicit prediction algorithm
        if algorithms[:prediction] and algorithms[:prediction][:method]
          case algorithms[:prediction][:method]
          when /Classifiction/
            model = LazarClassification.new
          when /Regression/
            model = LazarRegression.new 
          end
        # guess model type
        elsif prediction_feature.numeric? 
          model = LazarRegression.new 
        else
          model = LazarClassification.new
        end
        # set defaults
        if model.class == LazarClassification
          model.algorithms = {
            :similarity => {
              :descriptors => "fingerprint['MP2D']",
              :method => "Algorithm::Similarity.tanimoto",
              :min => 0.1
            },
            :prediction => {
              :descriptors => "fingerprint['MP2D']",
              :method => "Algorithm::Classification.weighted_majority_vote",
            },
            :feature_selection => nil,
          }
        elsif model.class == LazarRegression
          model.algorithms = {
            :similarity => {
              :descriptors => "fingerprint['MP2D']",
              :method => "Algorithm::Similarity.tanimoto",
              :min => 0.1
            },
            :prediction => {
              :descriptors => "fingerprint['MP2D']",
              :method => "Algorithm::Regression.local_caret",
              :parameters => "pls",
            },
            :feature_selection => nil,
          }
        end
        
        # overwrite defaults
        algorithms.each do |type,parameters|
          parameters.each do |p,v|
            model.algorithms[type][p] = v
          end if parameters
        end

        # set defaults for empty parameters
        model.prediction_feature_id = prediction_feature.id
        model.training_dataset_id = training_dataset.id
        model.name = "#{training_dataset.name} #{prediction_feature.name}" 

        #send(feature_selection_algorithm.to_sym) if feature_selection_algorithm
        model.save
        p model
        model
      end

      def correlation_filter 
        # TODO: speedup, single assignment of all features to R+ parallel computation of significance?
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
        feature_ids.select!{|fid| Feature.find(fid).category == feature_selection_algorithm_parameters[:category]} if feature_selection_algorithm_parameters[:category]
        feature_ids.each do |feature_id|
          feature_values = substances.collect{|s| s["physchem_descriptors"][feature_id].first if s["physchem_descriptors"][feature_id]}
          unless feature_values.uniq.size == 1
            R.assign "feature", feature_values
            begin
              R.eval "cor <- cor.test(tox,feature,method = 'pearson',use='pairwise')"
              pvalue = R.eval("cor$p.value").to_ruby
              if pvalue <= 0.05
                r = R.eval("cor$estimate").to_ruby
                self.relevant_features[feature_id] = {}
                self.relevant_features[feature_id]["pvalue"] = pvalue
                self.relevant_features[feature_id]["r"] = r
                self.relevant_features[feature_id]["mean"] = R.eval("mean(feature, na.rm=TRUE)").to_ruby
                self.relevant_features[feature_id]["sd"] = R.eval("sd(feature, na.rm=TRUE)").to_ruby
              end
            rescue
              warn "Correlation of '#{Feature.find(feature_id).name}' (#{feature_values}) with '#{Feature.find(prediction_feature_id).name}' (#{measurements}) failed."
            end
          end
        end
        self.relevant_features = self.relevant_features.sort{|a,b| a[1]["pvalue"] <=> b[1]["pvalue"]}.to_h
      end

      def predict_substance substance
        neighbor_algorithm_parameters = Hash[self.neighbor_algorithm_parameters.map{ |k, v| [k.to_sym, v] }] # convert string keys to symbols
        neighbor_algorithm_parameters[:relevant_features] = self.relevant_features if self.relevant_features
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
          m = neighbors.first["measurements"]
          if m.size == 1 # single measurement
            value = m.first
          else # multiple measurement
            if m.collect{|t| t.numeric?}.uniq == [true] # numeric
              value = m.median
            elsif m.uniq.size == 1 # single value
              value = m.first
            else # contradictory results
              # TODO add majority vote??
            end
          end
          prediction.merge!({:value => value, :probabilities => nil, :warning => "Only one similar compound in the training set. Predicting median of its experimental values.", :neighbors => neighbors}) if value
        else
          # call prediction algorithm
          klass,method = prediction_algorithm.split('.')
          params = prediction_algorithm_parameters.merge({:substance => substance, :neighbors => neighbors})
          result = Object.const_get(klass).send(method,params)
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

    end

    class LazarRegression < Lazar

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
        #prediction_model[:leave_one_out_validation_id] = Validation::LeaveOneOut.create(model).id
        prediction_model.save
        prediction_model
      end

    end

    class NanoPrediction < Prediction

      def self.from_json_dump dir, category
        Import::Enanomapper.import dir

        prediction_model = self.new(
          :endpoint => "log2(Net cell association)",
          :source => "https://data.enanomapper.net/",
          :species => "A549 human lung epithelial carcinoma cells",
          :unit => "log2(ug/Mg)"
        )
        params = {
          :feature_selection_algorithm => :correlation_filter,
          :feature_selection_algorithm_parameters => {:category => category},
          :neighbor_algorithm => "physchem_neighbors",
          :neighbor_algorithm_parameters => {:min_sim => 0.5},
          :prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression",
          :prediction_algorithm_parameters => {:method => 'rf'}, # random forests
          } 
        training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
        prediction_feature = Feature.find_or_create_by(name: "log2(Net cell association)", category: "TOX")
        #prediction_feature = Feature.find("579621b84de73e267b414e55")
        prediction_model[:prediction_feature_id] = prediction_feature.id
        model = Model::LazarRegression.create(prediction_feature, training_dataset, params)
        prediction_model[:model_id] = model.id
        repeated_cv = Validation::RepeatedCrossValidation.create model
        prediction_model[:repeated_crossvalidation_id] = Validation::RepeatedCrossValidation.create(model).id
        #prediction_model[:leave_one_out_validation_id] = Validation::LeaveOneOut.create(model).id
        prediction_model.save
        prediction_model
      end

    end

  end

end
