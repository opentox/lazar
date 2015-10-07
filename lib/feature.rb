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

  # Feature for database fingerprints
  # needs count for efficient retrieval (see compound.rb)
  class FingerprintSmarts < Smarts
    field :count, type: Integer
    def self.fingerprint
=begin
      @@fp4 ||= OpenTox::FingerprintSmarts.all
      unless @@fp4.size == 306
        @@fp4 = []
        # OpenBabel FP4 fingerprints
        # OpenBabel http://open-babel.readthedocs.org/en/latest/Fingerprints/intro.html
        # TODO investigate other types of fingerprints (MACCS)
        # OpenBabel http://open-babel.readthedocs.org/en/latest/Fingerprints/intro.html
        # http://www.dalkescientific.com/writings/diary/archive/2008/06/26/fingerprint_background.html
        # OpenBabel MNA http://openbabel.org/docs/dev/FileFormats/Multilevel_Neighborhoods_of_Atoms_(MNA).html#multilevel-neighborhoods-of-atoms-mna
        # Morgan ECFP, FCFP
        # http://cdk.github.io/cdk/1.5/docs/api/org/openscience/cdk/fingerprint/CircularFingerprinter.html
        # http://www.rdkit.org/docs/GettingStartedInPython.html
        # Chemfp
        # https://chemfp.readthedocs.org/en/latest/using-tools.html
        # CACTVS/PubChem

        File.open(File.join(File.dirname(__FILE__),"SMARTS_InteLigand.txt")).each do |l| 
          l.strip!
          unless l.empty? or l.match /^#/
            name,smarts = l.split(': ')
            @@fp4 << OpenTox::FingerprintSmarts.find_or_create_by(:name => name, :smarts => smarts) unless smarts.nil?
          end
        end
      end
      @@fp4
=end
    end
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
