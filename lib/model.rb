module OpenTox

  module Model

    class Lazar 

      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "models"

      attr_writer :independent_variables # store in GridFS to avoid Mongo database size limit problems

      field :name, type: String
      field :creator, type: String, default: __FILE__
      field :algorithms, type: Hash, default:{}
      field :training_dataset_id, type: BSON::ObjectId
      field :substance_ids, type: Array, default:[]
      field :prediction_feature_id, type: BSON::ObjectId
      field :dependent_variables, type: Array, default:[]
      field :descriptor_ids, type:Array, default:[]
      field :independent_variables_id, type: BSON::ObjectId
      field :fingerprints, type: Array, default:[]
      field :descriptor_weights, type: Array, default:[]
      field :descriptor_means, type: Array, default:[]
      field :descriptor_sds, type: Array, default:[]
      field :scaled_variables, type: Array, default:[]
      field :version, type: Hash, default:{}
      
      # Create a lazar model
      # @param [OpenTox::Dataset] training_dataset
      # @param [OpenTox::Feature, nil] prediction_feature
      #   By default the first feature of the training dataset will be predicted, specify a prediction_feature if you want to predict another feature
      # @param [Hash, nil] algorithms
      #   Default algorithms will be used, if no algorithms parameter is provided. The algorithms hash has the following keys: :descriptors (specifies the descriptors to be used for similarity calculations and local QSAR models), :similarity (similarity algorithm and threshold), :feature_selection (feature selection algorithm), :prediction (local QSAR algorithm). Default parameters are used for unspecified keys. 
      #
      # @return [OpenTox::Model::Lazar]
      def self.create prediction_feature:nil, training_dataset:, algorithms:{}
        bad_request_error "Please provide a prediction_feature and/or a training_dataset." unless prediction_feature or training_dataset
        prediction_feature = training_dataset.features.first unless prediction_feature
        # TODO: prediction_feature without training_dataset: use all available data

        # guess model type
        prediction_feature.numeric? ?  model = LazarRegression.new : model = LazarClassification.new

        model.prediction_feature_id = prediction_feature.id
        model.training_dataset_id = training_dataset.id
        model.name = "#{prediction_feature.name} (#{training_dataset.name})" 
        # git or gem versioning
        dir = File.dirname(__FILE__)
        path = File.expand_path("../", File.expand_path(dir))
        if Dir.exists?(dir+"/.git")
          commit = `git rev-parse HEAD`.chomp
          branch = `git rev-parse --abbrev-ref HEAD`.chomp
          url = `git config --get remote.origin.url`.chomp
          model.version = {:url => url, :branch => branch, :commit => commit}
        else
          version = File.open(path+"/VERSION", &:gets).chomp
          url = "https://rubygems.org/gems/lazar/versions/"+version
          model.version = {:url => url, :branch => "gem", :commit => version}
        end

        # set defaults#
        substance_classes = training_dataset.substances.collect{|s| s.class.to_s}.uniq
        bad_request_error "Cannot create models for mixed substance classes '#{substance_classes.join ', '}'." unless substance_classes.size == 1

        if substance_classes.first == "OpenTox::Compound"

          model.algorithms = {
            :descriptors => {
              :method => "fingerprint",
              :type => "MP2D",
            },
            :feature_selection => nil
          }

          if model.class == LazarClassification
            model.algorithms[:prediction] = {
                :method => "Algorithm::Classification.weighted_majority_vote",
            }
            model.algorithms[:similarity] = {
              :method => "Algorithm::Similarity.tanimoto",
              :min => 0.5,
            }
          elsif model.class == LazarRegression
            model.algorithms[:prediction] = {
              :method => "Algorithm::Caret.rf",
            }
            model.algorithms[:similarity] = {
              :method => "Algorithm::Similarity.tanimoto",
              :min => 0.5,
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
              :min => 0.5,
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
              model.algorithms[:descriptors].delete :categories if type == :descriptors and p == :type
            end
          else
            model.algorithms[type] = parameters
          end
        end if algorithms

        # parse dependent_variables from training dataset
        training_dataset.substances.each do |substance|
          values = training_dataset.values(substance,model.prediction_feature_id)
          values.each do |v|
            model.substance_ids << substance.id.to_s
            model.dependent_variables << v
          end if values
        end

        descriptor_method = model.algorithms[:descriptors][:method]
        model.independent_variables = []
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
          properties = model.substances.collect { |s| s.properties  }
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

      # Predict a substance (compound or nanoparticle)
      # @param [OpenTox::Substance]
      # @return [Hash]
      def predict_substance substance, threshold = self.algorithms[:similarity][:min]
        
        @independent_variables = Marshal.load $gridfs.find_one(_id: self.independent_variables_id).data
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
        
        prediction = {:warnings => [], :measurements => []}
        prediction[:warnings] << "Similarity threshold #{threshold} < #{algorithms[:similarity][:min]}, prediction may be out of applicability domain." if threshold < algorithms[:similarity][:min]
        neighbor_ids = []
        neighbor_similarities = []
        neighbor_dependent_variables = []
        neighbor_independent_variables = []

        # find neighbors
        substance_ids.each_with_index do |s,i|
          # handle query substance
          if substance.id.to_s == s
            prediction[:measurements] << dependent_variables[i]
            prediction[:info] = "Substance '#{substance.name}, id:#{substance.id}' has been excluded from neighbors, because it is identical with the query substance."
          else
            if fingerprints?
              neighbor_descriptors = fingerprints[i]
            else
              next if substance.is_a? Nanoparticle and substance.core != Nanoparticle.find(s).core # necessary for nanoparticle properties predictions
              neighbor_descriptors = scaled_variables.collect{|v| v[i]}
            end
            sim = Algorithm.run algorithms[:similarity][:method], [similarity_descriptors, neighbor_descriptors, descriptor_weights]
            if sim >= threshold
              neighbor_ids << s
              neighbor_similarities << sim
              neighbor_dependent_variables << dependent_variables[i]
              independent_variables.each_with_index do |c,j|
                neighbor_independent_variables[j] ||= []
                neighbor_independent_variables[j] << @independent_variables[j][i]
              end
            end
          end
        end

        measurements = nil
        
        if neighbor_similarities.empty?
          prediction[:value] = nil
          prediction[:warnings] << "Could not find similar substances with experimental data in the training dataset."
        elsif neighbor_similarities.size == 1
          prediction[:value] = nil
          prediction[:warnings] << "Cannot create prediction: Only one similar compound in the training set."
          prediction[:neighbors] = [{:id => neighbor_ids.first, :similarity => neighbor_similarities.first}]
        else
          query_descriptors.collect!{|d| d ? 1 : 0} if algorithms[:feature_selection] and algorithms[:descriptors][:method] == "fingerprint"
          # call prediction algorithm
          result = Algorithm.run algorithms[:prediction][:method], dependent_variables:neighbor_dependent_variables,independent_variables:neighbor_independent_variables ,weights:neighbor_similarities, query_variables:query_descriptors
          prediction.merge! result
          prediction[:neighbors] = neighbor_ids.collect_with_index{|id,i| {:id => id, :measurement => neighbor_dependent_variables[i], :similarity => neighbor_similarities[i]}}
          #if neighbor_similarities.max < algorithms[:similarity][:warn_min]
            #prediction[:warnings] << "Closest neighbor has similarity < #{algorithms[:similarity][:warn_min]}. Prediction may be out of applicability domain."
          #end
        end
        if prediction[:warnings].empty? or threshold < algorithms[:similarity][:min] or threshold <= 0.2
          prediction
        else # try again with a lower threshold
          predict_substance substance, 0.2
        end
      end

      # Predict a substance (compound or nanoparticle), an array of substances or a dataset
      # @param [OpenTox::Compound, OpenTox::Nanoparticle, Array<OpenTox::Substance>, OpenTox::Dataset]
      # @return [Hash, Array<Hash>, OpenTox::Dataset]
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
          prediction[:neighbors].sort!{|a,b| b[1] <=> a[1]} if prediction[:neighbors]# sort according to similarity
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

      # Save the model
      #   Stores independent_variables in GridFS to avoid Mongo database size limit problems
      def save
        file = Mongo::Grid::File.new(Marshal.dump(@independent_variables), :filename => "#{id}.independent_variables")
        self.independent_variables_id = $gridfs.insert_one(file)
        super
      end

      # Get independent variables
      # @return [Array<Array>]
      def independent_variables 
        @independent_variables ||= Marshal.load $gridfs.find_one(_id: self.independent_variables_id).data
        @independent_variables
      end

      # Get training dataset
      # @return [OpenTox::Dataset]
      def training_dataset
        Dataset.find(training_dataset_id)
      end

      # Get prediction feature
      # @return [OpenTox::Feature]
      def prediction_feature
        Feature.find(prediction_feature_id)
      end

      # Get training descriptors
      # @return [Array<OpenTox::Feature>]
      def descriptors
        descriptor_ids.collect{|id| Feature.find(id)}
      end

      # Get training substances
      # @return [Array<OpenTox::Substance>]
      def substances
        substance_ids.collect{|id| Substance.find(id)}
      end

      # Are fingerprints used as descriptors
      # @return [TrueClass, FalseClass]
      def fingerprints?
        algorithms[:descriptors][:method] == "fingerprint" ? true : false
      end

    end

    # Classification model
    class LazarClassification < Lazar
    end

    # Regression model
    class LazarRegression < Lazar
    end

    # Convenience class for generating and validating lazar models in a single step and predicting substances (compounds and nanoparticles), arrays of substances and datasets
    class Validation

      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps

      field :endpoint, type: String
      field :qmrf, type: Hash
      field :species, type: String
      field :source, type: String
      field :unit, type: String
      field :model_id, type: BSON::ObjectId
      field :repeated_crossvalidation_id, type: BSON::ObjectId

      # Predict a substance (compound or nanoparticle), an array of substances or a dataset
      # @param [OpenTox::Compound, OpenTox::Nanoparticle, Array<OpenTox::Substance>, OpenTox::Dataset]
      # @return [Hash, Array<Hash>, OpenTox::Dataset]
      def predict object
        model.predict object
      end

      # Get training dataset
      # @return [OpenTox::Dataset]
      def training_dataset
        model.training_dataset
      end

      # Get lazar model
      # @return [OpenTox::Model::Lazar]
      def model
        Lazar.find model_id
      end

      # Get algorithms
      # @return [Hash]
      def algorithms
        model.algorithms
      end

      # Get prediction feature
      # @return [OpenTox::Feature]
      def prediction_feature
        model.prediction_feature
      end

      # Get repeated crossvalidations
      # @return [OpenTox::Validation::RepeatedCrossValidation]
      def repeated_crossvalidation
        OpenTox::Validation::RepeatedCrossValidation.find repeated_crossvalidation_id # full class name required
      end

      # Get crossvalidations
      # @return [Array<OpenTox::CrossValidation]
      def crossvalidations
        repeated_crossvalidation.crossvalidations
      end

      # Is it a regression model
      # @return [TrueClass, FalseClass]
      def regression?
        model.is_a? LazarRegression
      end

      # Is it a classification model
      # @return [TrueClass, FalseClass]
      def classification?
        model.is_a? LazarClassification
      end

      # Create and validate a lazar model from a csv file with training data and a json file with metadata
      # @param [File] CSV file with two columns. The first line should contain either SMILES or InChI (first column) and the endpoint (second column). The first column should contain either the SMILES or InChI of the training compounds, the second column the training compounds toxic activities (qualitative or quantitative). Use -log10 transformed values for regression datasets. Add metadata to a JSON file with the same basename containing the fields "species", "endpoint", "source" and "unit" (regression only). You can find example training data at https://github.com/opentox/lazar-public-data.
      # @return [OpenTox::Model::Validation] lazar model with three independent 10-fold crossvalidations
      def self.from_csv_file file
        metadata_file = file.sub(/csv$/,"json")
        bad_request_error "No metadata file #{metadata_file}" unless File.exist? metadata_file
        model_validation = self.new JSON.parse(File.read(metadata_file))
        training_dataset = Dataset.from_csv_file file
        model = Lazar.create training_dataset: training_dataset
        model_validation[:model_id] = model.id
        model_validation[:repeated_crossvalidation_id] = OpenTox::Validation::RepeatedCrossValidation.create(model).id # full class name required
        model_validation.save
        model_validation
      end

      # Create and validate a nano-lazar model, import data from eNanoMapper if necessary
      #   nano-lazar methods are described in detail in https://github.com/enanomapper/nano-lazar-paper/blob/master/nano-lazar.pdf
      # @param [OpenTox::Dataset, nil] training_dataset
      # @param [OpenTox::Feature, nil] prediction_feature
      # @param [Hash, nil] algorithms
      # @return [OpenTox::Model::Validation] lazar model with five independent 10-fold crossvalidations
      def self.from_enanomapper training_dataset: nil, prediction_feature:nil, algorithms: nil
        
        # find/import training_dataset
        training_dataset ||= Dataset.where(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
        unless training_dataset # try to import 
          Import::Enanomapper.import
          training_dataset = Dataset.where(name: "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles").first
          bad_request_error "Cannot import 'Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles' dataset" unless training_dataset
        end
        prediction_feature ||= Feature.where(name: "log2(Net cell association)", category: "TOX").first

        model_validation = self.new(
          :endpoint => prediction_feature.name,
          :source => prediction_feature.source,
          :species => "A549 human lung epithelial carcinoma cells",
          :unit => prediction_feature.unit
        )
        model = LazarRegression.create prediction_feature: prediction_feature, training_dataset: training_dataset, algorithms: algorithms
        model_validation[:model_id] = model.id
        repeated_cv = OpenTox::Validation::RepeatedCrossValidation.create model, 10, 5
        model_validation[:repeated_crossvalidation_id] = repeated_cv.id
        model_validation.save
        model_validation
      end

    end

  end

end
