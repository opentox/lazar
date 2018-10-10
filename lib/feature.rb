module OpenTox

  # Basic feature class
  class Feature
  end

  # Original ID (e.g. from CSV input)
  class OriginalId < Feature
    field :dataset_id, type: BSON::ObjectId
  end

  # Feature for categorical variables
  class NominalFeature < Feature
    field :accept_values, type: Array
  end

  # Feature for quantitative variables
  class NumericFeature < Feature
    field :unit, type: String
  end

  # Nominal biological activity
  class NominalBioActivity < NominalFeature
    field :original_feature_id, type: BSON::ObjectId
    field :transformation, type: Hash
  end

  # Numeric biological activity
  class NumericBioActivity < NumericFeature
    field :original_feature_id, type: BSON::ObjectId
    field :transformation, type: String
  end

  # Nominal lazar prediction
  class NominalLazarPrediction < NominalFeature
    field :model_id, type: BSON::ObjectId
    field :training_feature_id, type: BSON::ObjectId
  end

  # Numeric lazar prediction
  class NumericLazarPrediction < NumericFeature
    field :model_id, type: BSON::ObjectId
    field :training_feature_id, type: BSON::ObjectId
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
