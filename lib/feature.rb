module OpenTox

  # Original ID (e.g. from CSV input)
  class OriginalId < Feature
    field :dataset_id, type: BSON::ObjectId
  end

  # Original SMILES (e.g. from CSV input)
  class OriginalSmiles < Feature
    field :dataset_id, type: BSON::ObjectId
  end

  # Warnings
  class Warnings < Feature
    field :dataset_id, type: BSON::ObjectId
  end

  # Categorical variables
  class NominalFeature < Feature
    field :accept_values, type: Array
  end

  # Quantitative variables
  class NumericFeature < Feature
    field :unit, type: String
  end

  # Nominal biological activity
  class NominalBioActivity < NominalFeature
  end

  # Numeric biological activity
  class NumericBioActivity < NumericFeature
  end

  # Merged nominal biological activity
  class MergedNominalBioActivity < NominalFeature
    field :original_feature_ids, type: Array
  end

  # Transformed nominal biological activity
  class TransformedNominalBioActivity < NominalFeature
    field :original_feature_id, type: BSON::ObjectId
    field :transformation, type: Hash
  end

  # Transformed numeric biological activity
  class TransformedNumericBioActivity < NumericFeature
    field :original_feature_id, type: BSON::ObjectId
    field :transformation, type: String
  end

  # Nominal lazar prediction
  class NominalLazarPrediction < NominalFeature
    field :model_id, type: BSON::ObjectId
    field :training_feature_id, type: BSON::ObjectId
    def name
      "#{self[:name]} Prediction"
    end
  end

  class LazarPredictionProbability < NominalLazarPrediction
    def name
      "probability(#{self[:name]})"
    end
  end

  # Numeric lazar prediction
  class NumericLazarPrediction < NumericFeature
    field :model_id, type: BSON::ObjectId
    field :training_feature_id, type: BSON::ObjectId
    def name
      "#{name} Prediction"
    end
  end

  class LazarPredictionInterval < NumericLazarPrediction
    def name
      "prediction_interval_#{self[:name]}"
    end
  end

  class NominalSubstanceProperty < NominalFeature
  end

  class NumericSubstanceProperty < NumericFeature
  end

  class NanoParticleProperty < NumericSubstanceProperty
    field :category, type: String
    field :conditions, type: Hash
  end

  # Feature for SMARTS fragments
  class Smarts < Feature
    field :smarts, type: String 
    index "smarts" => 1
    # Create feature from SMARTS string
    # @param [String]
    # @return [OpenTox::Feature]
    def self.from_smarts smarts
      self.find_or_create_by :smarts => smarts
    end
  end

end
