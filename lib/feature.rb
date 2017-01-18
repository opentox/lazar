module OpenTox

  # Basic feature class
  class Feature
    field :measured, type: Boolean
    field :calculated, type: Boolean
    field :category, type: String
    field :unit, type: String
    field :conditions, type: Hash

    # Is it a nominal feature
    # @return [TrueClass,FalseClass]
    def nominal?
      self.class == NominalFeature
    end

    # Is it a numeric feature
    # @return [TrueClass,FalseClass]
    def numeric?
      self.class == NumericFeature
    end
  end

  # Feature for categorical variables
  class NominalFeature < Feature
    field :accept_values, type: Array
  end

  # Feature for quantitative variables
  class NumericFeature < Feature
  end

  # Feature for SMARTS fragments
  class Smarts < NominalFeature
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
