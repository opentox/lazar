module OpenTox

  # Nanoparticles
  class Nanoparticle < Substance
    include OpenTox

    field :core_id, type: String, default: nil
    field :coating_ids, type: Array, default: []

    # Get core compound
    # @return [OpenTox::Compound]
    def core
      Compound.find core_id
    end

    # Get coatings
    # @return [Array<OpenTox::Compound>]
    def coating
      coating_ids.collect{|i| Compound.find i }
    end

    # Get nanoparticle fingerprint (union of core and coating fingerprints)
    # @param [String] fingerprint type
    # @return [Array<String>] 
    def fingerprint type=DEFAULT_FINGERPRINT
      core_fp = core.fingerprint type
      coating_fp = coating.collect{|c| c.fingerprint type}.flatten.uniq.compact
      (core_fp.empty? or coating_fp.empty?) ? [] : (core_fp+coating_fp).uniq.compact
    end

    # Calculate physchem properties
    # @param [Array<Hash>] list of descriptors
    # @return [Array<Float>]
    def calculate_properties descriptors=PhysChem::OPENBABEL
      if core.smiles and !coating.collect{|c| c.smiles}.compact.empty?
        core_prop = core.calculate_properties descriptors
        coating_prop = coating.collect{|c| c.calculate_properties descriptors if c.smiles}
        descriptors.collect_with_index{|d,i| [core_prop[i],coating_prop.collect{|c| c[i] if c}]}
      end
    end

    # Add (measured) feature values
    # @param [OpenTox::Feature]
    # @param [TrueClass,FalseClass,Float] 
    # @param [OpenTox::Dataset]
    def add_feature feature, value, dataset
      unless feature.name == "ATOMIC COMPOSITION" or feature.name == "FUNCTIONAL GROUP" # redundand
        case feature.category
        when "P-CHEM"
          properties[feature.id.to_s] ||= []
          properties[feature.id.to_s] << value
          properties[feature.id.to_s].uniq!
        when "Proteomics"
          properties[feature.id.to_s] ||= []
          properties[feature.id.to_s] << value
          properties[feature.id.to_s].uniq!
        when "TOX"
          if feature.name.match("Cell Viability Assay") and !feature.name.match("SLOPE") # -log10 transformation
            value = -Math.log10(value)
            feature.unit = "-log10(#{feature.unit})" unless feature.unit.match "log10"
            feature.warnings += ["-log10 transformed values"]  unless feature.warnings.include? "-log10 transformed values"
            feature.save
          end
          dataset.add self, feature, value
        else
          warn "Unknown feature type '#{feature.category}'. Value '#{value}' not inserted."
        end
        dataset_ids << dataset.id
        dataset_ids.uniq!
      end
    end

    # Parse values from Ambit database
    # @param [OpenTox::Feature]
    # @param [TrueClass,FalseClass,Float]
    # @param [OpenTox::Dataset]
    def parse_ambit_value feature, v, dataset
      # TODO add study id to warnings
      v.delete "unit"
      # TODO: ppm instead of weights
      if v.keys == ["textValue"]
        add_feature feature, v["textValue"], dataset
      elsif v.keys == ["loValue"]
        add_feature feature, v["loValue"], dataset
      elsif v.keys.size == 2 and v["errorValue"]
        add_feature feature, v["loValue"], dataset
        #warn "Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
      elsif v.keys.size == 2 and v["loQualifier"] == "mean"
        add_feature feature, v["loValue"], dataset
        #warn "'#{feature.name}' is a mean value. Original data is not available."
      elsif v.keys.size == 2 and v["loQualifier"] #== ">="
        #warn "Only min value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 2 and v["upQualifier"] #== ">="
        #warn "Only max value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 3 and v["loValue"] and v["loQualifier"].nil? and v["upQualifier"].nil?
        add_feature feature, v["loValue"], dataset
        #warn "loQualifier and upQualifier are empty."
      elsif v.keys.size == 3 and v["loValue"] and v["loQualifier"] == "" and v["upQualifier"] == ""
        add_feature feature, v["loValue"], dataset
        #warn "loQualifier and upQualifier are empty."
      elsif v.keys.size == 4 and v["loValue"] and v["loQualifier"].nil? and v["upQualifier"].nil?
        add_feature feature, v["loValue"], dataset
        #warn "loQualifier and upQualifier are empty."
      elsif v.size == 4 and v["loQualifier"] and v["upQualifier"] and v["loValue"] and v["upValue"]
        #add_feature feature, [v["loValue"],v["upValue"]].mean, dataset
        #warn "Using mean value of range #{v["loValue"]} - #{v["upValue"]} for '#{feature.name}'. Original data is not available."
      elsif v.size == 4 and v["loQualifier"] == "mean" and v["errorValue"]
        #warn "'#{feature.name}' is a mean value. Original data is not available. Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
        add_feature feature, v["loValue"], dataset
      elsif v == {} # do nothing
      else
        warn "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
      end
    end

  end
end
