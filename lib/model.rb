module OpenTox

  module Model

    class Lazar 

      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "models"

      field :name, type: String
      field :creator, type: String, default: __FILE__
      field :algorithms, type: Hash, default:{}
      field :training_dataset_id, type: BSON::ObjectId
      field :substance_ids, type: Array, default:[]
      field :prediction_feature_id, type: BSON::ObjectId
      field :dependent_variables, type: Array, default:[]
      field :descriptor_ids, type:Array, default:[]
      field :independent_variables, type: Array, default:[]
      field :fingerprints, type: Array, default:[]
      field :descriptor_weights, type: Array, default:[]
      field :descriptor_means, type: Array, default:[]
      field :descriptor_sds, type: Array, default:[]
      field :scaled_variables, type: Array, default:[]
      field :version, type: Hash, default:{}
      
      def self.create prediction_feature:nil, training_dataset:nil, algorithms:{}
        bad_request_error "Please provide a prediction_feature and/or a training_dataset." unless prediction_feature or training_dataset
        prediction_feature = training_dataset.features.first unless prediction_feature
        # TODO: prediction_feature without training_dataset: use all available data

        # guess model type
        prediction_feature.numeric? ?  model = LazarRegression.new : model = LazarClassification.new

        model.prediction_feature_id = prediction_feature.id
        model.training_dataset_id = training_dataset.id
        model.name = "#{prediction_feature.name} (#{training_dataset.name})" 
        # TODO: check if this works for gem version, add gem versioning?
        dir = File.dirname(__FILE__)
        commit = `cd #{dir}; git rev-parse HEAD`.chomp
        branch = `cd #{dir}; git rev-parse --abbrev-ref HEAD`.chomp
        url = `cd #{dir}; git config --get remote.origin.url`.chomp
        if branch
          model.version = {:url => url, :branch => branch, :commit => commit}
        else
          model.version = {:warning => "git is not installed"}
        end

        # set defaults
        substance_classes = training_dataset.substances.collect{|s| s.class.to_s}.uniq
        bad_request_error "Cannot create models for mixed substance classes '#{substance_classes.join ', '}'." unless substance_classes.size == 1

        if substance_classes.first == "OpenTox::Compound"

          model.algorithms = {
            :descriptors => {
              :method => "fingerprint",
              :type => "MP2D",
            },
            :similarity => {
              :method => "Algorithm::Similarity.tanimoto",
              :min => 0.1
            },
            :feature_selection => nil
          }

          if model.class == LazarClassification
            model.algorithms[:prediction] = {
                :method => "Algorithm::Classification.weighted_majority_vote",
            }
          elsif model.class == LazarRegression
            model.algorithms[:prediction] = {
              :method => "Algorithm::Caret.pls",
            }
          end

        elsif substance_classes.first == "OpenTox::Nanoparticle"
          model.algorithms = {
            :descriptors => {
              :method => "properties",
              :categories => ["P-CHEM"],
            },
            :similarity => {
              :method => "Algorithm::Similarity.weighted_cosine",
              :min => 0.5
            },
            :prediction => {
              :method => "Algorithm::Caret.rf",
            },
            :feature_selection => {
              :method => "Algorithm::FeatureSelection.correlation_filter",
            },
          }
        else
          bad_request_error "Cannot create models for #{substance_classes.first}."
        end
        
        # overwrite defaults with explicit parameters
        algorithms.each do |type,parameters|
          if parameters and parameters.is_a? Hash
            parameters.each do |p,v|
              model.algorithms[type] ||= {}
              model.algorithms[type][p] = v
            end
          else
            model.algorithms[type] = parameters
          end
        end

        # parse dependent_variables from training dataset
        training_dataset.substances.each do |substance|
          values = training_dataset.values(substance,model.prediction_feature_id)
          values.each do |v|
            model.substance_ids << substance.id.to_s
            model.dependent_variables << v
          end if values
        end

        descriptor_method = model.algorithms[:descriptors][:method]
        case descriptor_method
        # parse fingerprints
        when "fingerprint"
          type = model.algorithms[:descriptors][:type]
          model.substances.each_with_index do |s,i|
            model.fingerprints[i] ||= [] 
            model.fingerprints[i] += s.fingerprint(type)
            model.fingerprints[i].uniq!
          end
          model.descriptor_ids = model.fingerprints.flatten.uniq
          model.descriptor_ids.each do |d|
            # resulting model may break BSON size limit (e.g. f Kazius dataset)
            model.independent_variables << model.substance_ids.collect_with_index{|s,i| model.fingerprints[i].include? d} if model.algorithms[:prediction][:method].match /Caret/
          end
        # calculate physchem properties
        when "calculate_properties"
          features = model.algorithms[:descriptors][:features]
          model.descriptor_ids = features.collect{|f| f.id.to_s}
          model.algorithms[:descriptors].delete(:features)
          model.algorithms[:descriptors].delete(:type)
          model.substances.each_with_index do |s,i|
            props = s.calculate_properties(features)
            props.each_with_index do |v,j|
              model.independent_variables[j] ||= []
              model.independent_variables[j][i] = v
            end if props and !props.empty?
          end
        # parse independent_variables
        when "properties"
          categories = model.algorithms[:descriptors][:categories]
          feature_ids = []
          categories.each do |category|
            Feature.where(category:category).each{|f| feature_ids << f.id.to_s}
          end
          #p feature_ids
          #properties = Nanoparticle.all.collect { |s| p s.name; p s.id; p s.properties }
          properties = model.substances.collect { |s| s.properties  }
          #p properties
          property_ids = properties.collect{|p| p.keys}.flatten.uniq
          model.descriptor_ids = feature_ids & property_ids
          model.independent_variables = model.descriptor_ids.collect{|i| properties.collect{|p| p[i] ? p[i].median : nil}}
        else
          bad_request_error "Descriptor method '#{descriptor_method}' not implemented."
        end
        
        if model.algorithms[:feature_selection] and model.algorithms[:feature_selection][:method]
          model = Algorithm.run model.algorithms[:feature_selection][:method], model
        end

        # scale independent_variables
        unless model.fingerprints?
          model.independent_variables.each_with_index do |var,i|
            model.descriptor_means[i] = var.mean
            model.descriptor_sds[i] =  var.standard_deviation
            model.scaled_variables << var.collect{|v| v ? (v-model.descriptor_means[i])/model.descriptor_sds[i] : nil}
          end
        end
        model.save
        model
      end

      def predict_substance substance
        
        case algorithms[:similarity][:method]
        when /tanimoto/ # binary features
          similarity_descriptors = substance.fingerprint algorithms[:descriptors][:type]
          # TODO this excludes descriptors only present in the query substance
          # use for applicability domain?
          query_descriptors = descriptor_ids.collect{|id| similarity_descriptors.include? id}
        when /euclid|cosine/ # quantitative features
          if algorithms[:descriptors][:method] == "calculate_properties" # calculate descriptors
            features = descriptor_ids.collect{|id| Feature.find(id)}
            query_descriptors = substance.calculate_properties(features)
            similarity_descriptors = query_descriptors.collect_with_index{|v,i| (v-descriptor_means[i])/descriptor_sds[i]}
          else
            similarity_descriptors = []
            query_descriptors = []
            descriptor_ids.each_with_index do |id,i|
              prop = substance.properties[id]
              prop = prop.median if prop.is_a? Array # measured
              if prop
                similarity_descriptors[i] = (prop-descriptor_means[i])/descriptor_sds[i]
                query_descriptors[i] = prop
              end
            end
          end
        else
          bad_request_error "Unknown descriptor type '#{descriptors}' for similarity method '#{similarity[:method]}'."
        end
        
        prediction = {}
        neighbor_ids = []
        neighbor_similarities = []
        neighbor_dependent_variables = []
        neighbor_independent_variables = []

        prediction = {}
        # find neighbors
        substance_ids.each_with_index do |s,i|
          # handle query substance
          if substance.id.to_s == s
            prediction[:measurements] ||= []
            prediction[:measurements] << dependent_variables[i]
            prediction[:warning] = "Substance '#{substance.name}, id:#{substance.id}' has been excluded from neighbors, because it is identical with the query substance."
          else
            next if substance.is_a? Nanoparticle and substance.core != Nanoparticle.find(s).core
            if fingerprints?
              neighbor_descriptors = fingerprints[i]
            else
              neighbor_descriptors = scaled_variables.collect{|v| v[i]}
            end
            sim = Algorithm.run algorithms[:similarity][:method], [similarity_descriptors, neighbor_descriptors, descriptor_weights]
            if sim >= algorithms[:similarity][:min]
              neighbor_ids << s
              neighbor_similarities << sim
              neighbor_dependent_variables << dependent_variables[i]
              independent_variables.each_with_index do |c,j|
                neighbor_independent_variables[j] ||= []
                neighbor_independent_variables[j] << independent_variables[j][i]
              end
            end
          end
        end

        measurements = nil
        
        if neighbor_similarities.empty?
          prediction.merge!({:value => nil,:warning => "Could not find similar substances with experimental data in the training dataset.",:neighbors => []})
        elsif neighbor_similarities.size == 1
          prediction.merge!({:value => dependent_variables.first, :probabilities => nil, :warning => "Only one similar compound in the training set. Predicting its experimental value.", :neighbors => [{:id => neighbor_ids.first, :similarity => neighbor_similarities.first}]})
        else
          # call prediction algorithm
          result = Algorithm.run algorithms[:prediction][:method], dependent_variables:neighbor_dependent_variables,independent_variables:neighbor_independent_variables ,weights:neighbor_similarities, query_variables:query_descriptors
          prediction.merge! result
          prediction[:neighbors] = neighbor_ids.collect_with_index{|id,i| {:id => id, :measurement => neighbor_dependent_variables[i], :similarity => neighbor_similarities[i]}}
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
          bad_request_error "Please provide a OpenTox::Compound an Array of OpenTox::Substances or an OpenTox::Dataset as parameter."
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
          # prepare prediction dataset
          measurement_feature = Feature.find prediction_feature_id

          prediction_feature = NumericFeature.find_or_create_by( "name" => measurement_feature.name + " (Prediction)" )
          prediction_dataset = LazarPrediction.create(
            :name => "Lazar prediction for #{prediction_feature.name}",
            :creator =>  __FILE__,
            :prediction_feature_id => prediction_feature.id,
            :predictions => predictions
          )
          return prediction_dataset
        end

      end

      def training_dataset
        Dataset.find(training_dataset_id)
      end

      def prediction_feature
        Feature.find(prediction_feature_id)
      end

      def descriptors
        descriptor_ids.collect{|id| Feature.find(id)}
      end

      def substances
        substance_ids.collect{|id| Substance.find(id)}
      end

      def fingerprints?
        algorithms[:descriptors][:method] == "fingerprint" ? true : false
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
        model.predict object
      end

      def training_dataset
        model.training_dataset
      end

      def model
        Lazar.find model_id
      end

      def prediction_feature
        model.prediction_feature
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
        model = Lazar.create training_dataset: training_dataset
        prediction_model[:model_id] = model.id
        prediction_model[:repeated_crossvalidation_id] = Validation::RepeatedCrossValidation.create(model).id
        #prediction_model[:leave_one_out_validation_id] = Validation::LeaveOneOut.create(model).id
        prediction_model.save
        prediction_model
      end

    end

    class NanoPrediction < Prediction

      def self.from_json_dump dir, category
        Import::Enanomapper.import dir
        training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
        unless training_dataset
          Import::Enanomapper.import File.join(File.dirname(__FILE__),"data","enm")
          training_dataset = Dataset.where(name: "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
        end
        prediction_model = self.new(
          :endpoint => "log2(Net cell association)",
          :source => "https://data.enanomapper.net/",
          :species => "A549 human lung epithelial carcinoma cells",
          :unit => "log2(ug/Mg)"
        )
        prediction_feature = Feature.where(name: "log2(Net cell association)", category: "TOX").first
        model = Model::LazarRegression.create(prediction_feature: prediction_feature, training_dataset: training_dataset)
        prediction_model[:model_id] = model.id
        repeated_cv = Validation::RepeatedCrossValidation.create model
        prediction_model[:repeated_crossvalidation_id] = Validation::RepeatedCrossValidation.create(model).id
        #prediction_model[:leave_one_out_validation_id] = Validation::LeaveOneOut.create(model).id
        prediction_model.save
        prediction_model
      end

      def self.create dir: dir, algorithms: algorithms
        training_dataset = Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
        unless training_dataset
          Import::Enanomapper.import dir
          training_dataset = Dataset.where(name: "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
        end
        prediction_model = self.new(
          :endpoint => "log2(Net cell association)",
          :source => "https://data.enanomapper.net/",
          :species => "A549 human lung epithelial carcinoma cells",
          :unit => "log2(ug/Mg)"
        )
        prediction_feature = Feature.where(name: "log2(Net cell association)", category: "TOX").first
        model = Model::LazarRegression.create(prediction_feature: prediction_feature, training_dataset: training_dataset, algorithms: algorithms)
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
