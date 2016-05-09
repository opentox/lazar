module OpenTox

  class Nanoparticle < Substance
    include OpenTox

    field :core, type: String
    field :coating, type: Array, default: []
    field :bundles, type: Array, default: []
    field :proteomics, type: Hash, default: {}

    def nanoparticle_neighbors params
      dataset = Dataset.find(params[:training_dataset_id])
      Dataset.find(params[:training_dataset_id]).nanoparticles.collect do |np|
        np["tanimoto"] = 1
        np unless np.toxicities.empty?
      end.compact
    end

    def add_feature feature, value, dataset_id
      case feature.category
      when "P-CHEM"
        physchem_descriptors[feature.id.to_s] ||= []
        physchem_descriptors[feature.id.to_s] << value
        physchem_descriptors[feature.id.to_s].uniq!
      when "Proteomics"
        proteomics[feature.id.to_s] ||= []
        proteomics[feature.id.to_s] << value
        proteomics[feature.id.to_s].uniq!
      when "TOX"
        toxicities[feature.id.to_s] ||= {}
        toxicities[feature.id.to_s][dataset_id.to_s] ||= []
        # TODO generic way of parsing TOX values
        if feature.name == "7.99 Toxicity (other) ICP-AES" and feature.unit == "mL/ug(Mg)" 
          toxicities[feature.id.to_s][dataset_id.to_s] << -Math.log10(value)
        else
          toxicities[feature.id.to_s][dataset_id.to_s] << value
        end
        toxicities[feature.id.to_s][dataset_id.to_s].uniq!
      else
        warn "Unknown feature type '#{feature.category}'. Value '#{value}' not inserted."
      end
    end

    def parse_ambit_value feature, v, dataset_id
      v.delete "unit"
      # TODO: ppm instead of weights
      if v.keys == ["textValue"]
        add_feature feature, v["textValue"], dataset_id
      elsif v.keys == ["loValue"]
        add_feature feature, v["loValue"], dataset_id
      elsif v.keys.size == 2 and v["errorValue"]
        add_feature feature, v["loValue"], dataset_id
        warn "Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
      elsif v.keys.size == 2 and v["loQualifier"] == "mean"
        add_feature feature, v["loValue"], dataset_id
        warn "'#{feature.name}' is a mean value. Original data is not available."
      elsif v.keys.size == 2 and v["loQualifier"] #== ">="
        warn "Only min value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 2 and v["upQualifier"] #== ">="
        warn "Only max value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 3 and v["loValue"] and v["loQualifier"].nil? and v["upQualifier"].nil?
        add_feature feature, v["loValue"], dataset_id
        warn "loQualifier and upQualifier are empty."
      elsif v.keys.size == 3 and v["loValue"] and v["loQualifier"] == "" and v["upQualifier"] == ""
        add_feature feature, v["loValue"], dataset_id
        warn "loQualifier and upQualifier are empty."
      elsif v.keys.size == 4 and v["loValue"] and v["loQualifier"].nil? and v["upQualifier"].nil?
        add_feature feature, v["loValue"], dataset_id
        warn "loQualifier and upQualifier are empty."
      elsif v.size == 4 and v["loQualifier"] and v["upQualifier"] and v["loValue"] and v["upValue"]
        add_feature feature, [v["loValue"],v["upValue"]].mean, dataset_id
        warn "Using mean value of range #{v["loValue"]} - #{v["upValue"]} for '#{feature.name}'. Original data is not available."
      elsif v.size == 4 and v["loQualifier"] == "mean" and v["errorValue"]
        warn "'#{feature.name}' is a mean value. Original data is not available. Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
        add_feature feature, v["loValue"], dataset_id
      elsif v == {} # do nothing
      else
        warn "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
      end
    end

  end
end
