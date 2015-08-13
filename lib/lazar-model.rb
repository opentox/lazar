module OpenTox

  module Model

    class Lazar 
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "models"

      field :title, type: String
      field :creator, type: String, default: __FILE__
      # datasets
      field :training_dataset_id, type: BSON::ObjectId
      # algorithms
      field :prediction_algorithm, type: String
      field :neighbor_algorithm, type: String
      field :neighbor_algorithm_parameters, type: Hash
      # prediction feature
      field :prediction_feature_id, type: BSON::ObjectId

      attr_accessor :prediction_dataset
      attr_accessor :training_dataset

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
        lazar.title = prediction_feature.title 

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
          predictions << Algorithm.run(prediction_algorithm, neighbors)
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
            :title => "Lazar prediction for #{prediction_feature.title}",
            :creator =>  __FILE__,
            :prediction_feature_id => prediction_feature.id

          )
          confidence_feature = OpenTox::NumericFeature.find_or_create_by( "title" => "Prediction confidence" )
          # TODO move into warnings field
          warning_feature = OpenTox::NominalFeature.find_or_create_by("title" => "Warnings")
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
      #field :feature_dataset_id, type: BSON::ObjectId
      #field :feature_calculation_algorithm, type: String

      def self.create training_dataset
        model = super(training_dataset)
        model.update "_type" => self.to_s # adjust class
        model = self.find model.id # adjust class
        model.neighbor_algorithm = "OpenTox::Algorithm::Neighbor.fminer_similarity"
        model.neighbor_algorithm_parameters = {
          :feature_calculation_algorithm => "OpenTox::Algorithm::Descriptor.smarts_match",
          :feature_dataset_id => Algorithm::Fminer.bbrc(training_dataset).id,
          :min_sim => 0.3
        }
        model.save
        model
      end

=begin
      def predict object

        t = Time.now
        at = Time.now

        @training_dataset = OpenTox::Dataset.find(training_dataset_id)
        @feature_dataset = OpenTox::Dataset.find(feature_dataset_id)

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

        $logger.debug "Setup: #{Time.now-t}"
        t = Time.now

        @query_fingerprint = Algorithm.run(feature_calculation_algorithm, compounds, @feature_dataset.features.collect{|f| f.name} )

        $logger.debug "Query fingerprint calculation: #{Time.now-t}"
        t = Time.now

        predictions = []
        prediction_feature = OpenTox::Feature.find prediction_feature_id
        tt = 0
        pt = 0
        nt = 0
        st = 0
        nit = 0
        @training_fingerprints ||= @feature_dataset.data_entries
        compounds.each_with_index do |compound,c|
          t = Time.new

          $logger.debug "predict compound #{c+1}/#{compounds.size} #{compound.inchi}"

          database_activities = @training_dataset.values(compound,prediction_feature)
          if database_activities and !database_activities.empty?
            database_activities = database_activities.first if database_activities.size == 1
            $logger.debug "Compound #{compound.inchi} occurs in training dataset with activity #{database_activities}"
            predictions << {:compound => compound, :value => database_activities, :confidence => "measured"}
            next
          else

            #training_fingerprints = @feature_dataset.data_entries
            query_fingerprint = @query_fingerprint[c]
            neighbors = []
            tt += Time.now-t
            t = Time.new
            

            # find neighbors
            @training_fingerprints.each_with_index do |fingerprint, i|
              ts = Time.new
              sim = Algorithm.run(similarity_algorithm,fingerprint, query_fingerprint)
              st += Time.now-ts
              ts = Time.new
              if sim > self.min_sim
                if prediction_algorithm =~ /Regression/
                  neighbors << [@feature_dataset.compound_ids[i],sim,training_activities[i], fingerprint]
                else
                  neighbors << [@feature_dataset.compound_ids[i],sim,training_activities[i]] # use compound_ids, instantiation of Compounds is too time consuming
                end
              end
              nit += Time.now-ts
            end

            if neighbors.empty?
              predictions << {:compound => compound, :value => nil, :confidence => nil, :warning => "No neighbors with similarity > #{min_sim} in dataset #{training_dataset.id}"}
              next
            end
            nt += Time.now-t
            t = Time.new

            if prediction_algorithm =~ /Regression/
              prediction = Algorithm.run(prediction_algorithm, neighbors, :min_train_performance => self.min_train_performance)
            else
              prediction = Algorithm.run(prediction_algorithm, neighbors)
            end
            prediction[:compound] = compound
            prediction[:neighbors] = neighbors.sort{|a,b| b[1] <=> a[1]} # sort with ascending similarities


            # AM: transform to original space (TODO)
            #confidence_value = ((confidence_value+1.0)/2.0).abs if prediction.first and similarity_algorithm =~ /cosine/


            $logger.debug "predicted value: #{prediction[:value]}, confidence: #{prediction[:confidence]}"
            predictions << prediction
            pt += Time.now-t
          end

        end 
        $logger.debug "Transform time: #{tt}"
        $logger.debug "Neighbor search time: #{nt} (Similarity calculation: #{st}, Neighbor insert: #{nit})"
        $logger.debug "Prediction time: #{pt}"
        $logger.debug "Total prediction time: #{Time.now-at}"

        # serialize result
        case object.class.to_s
        when "OpenTox::Compound"
          return predictions.first
        when "Array"
          return predictions
        when "OpenTox::Dataset"
          # prepare prediction dataset
          prediction_dataset = LazarPrediction.new(
            :title => "Lazar prediction for #{prediction_feature.title}",
            :creator =>  __FILE__,
            :prediction_feature_id => prediction_feature.id

          )
          confidence_feature = OpenTox::NumericFeature.find_or_create_by( "title" => "Prediction confidence" )
          warning_feature = OpenTox::NominalFeature.find_or_create_by("title" => "Warnings")
          prediction_dataset.features = [ prediction_feature, confidence_feature, warning_feature ]
          prediction_dataset.compounds = compounds
          prediction_dataset.data_entries = predictions.collect{|p| [p[:value], p[:confidence],p[:warning]]}
          prediction_dataset.save_all
          return prediction_dataset
        end

      end
=end
    end

    class LazarRegression < Lazar

      def initialize
        super
        self.neighbor_algorithm = "OpenTox::Algorithm::Neighbor.fingerprint_similarity"
        self.prediction_algorithm = "OpenTox::Algorithm::Regression.weighted_average" 
        self.neighbor_algorithm_parameters = {:min_sim => 0.7}
      end

    end

    class PredictionModel < Lazar
      field :category, type: String
      field :endpoint, type: String
      field :crossvalidation_id, type: BSON::ObjectId
    end

  end

end

