module OpenTox

  # Basic feature class
  class Feature
    field :nominal, type: Boolean
    field :numeric, type: Boolean
    field :measured, type: Boolean
    field :calculated, type: Boolean
    field :unit, type: String
  end

  # Feature for categorical variables
  class NominalFeature < Feature
    field :accept_values, type: Array
    def initialize params
      super params
      nominal = true
    end
  end

  # Feature for quantitative variables
  class NumericFeature < Feature
    def initialize params
      super params
      numeric = true
    end
  end

  # Feature for SMARTS fragments
  class Smarts < NominalFeature
    field :smarts, type: String 
    index "smarts" => 1
    def self.from_smarts smarts
      self.find_or_create_by :smarts => smarts
    end
  end

  # Feature for categorical bioassay results
  class NominalBioAssay < NominalFeature
  end

  # Feature for quantitative bioassay results
  class NumericBioAssay < NumericFeature
  end

end
