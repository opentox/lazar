module OpenTox

  # Basic feature class
  class Feature
    field :nominal, type: Boolean
    field :numeric, type: Boolean
    field :measured, type: Boolean
  end

  # Feature for categorical variables
  class NominalFeature < Feature
    # TODO check if accept_values are still needed 
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

  # Feature for supervised fragments from Fminer algorithm
  class FminerSmarts < Smarts
    field :p_value, type: Float
    # TODO check if effect is used
    field :effect, type: String
    field :dataset_id 
  end

  # Feature for physico-chemical descriptors
  class PhysChemDescriptor < NumericFeature
    field :algorithm, type: String, default: "OpenTox::Algorithm::Descriptor.physchem"
    field :parameters, type: Hash
    field :creator, type: String
  end

  # Feature for categorical bioassay results
  class NominalBioAssay < NominalFeature
  end

  # Feature for quantitative bioassay results
  class NumericBioAssay < NumericFeature
  end

end
