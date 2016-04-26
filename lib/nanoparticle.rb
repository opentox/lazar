module OpenTox

  class Nanoparticle < Substance
    include OpenTox

    field :core, type: String
    field :coating, type: Array, default: []
    field :bundles, type: Array, default: []

    def nanoparticle_neighbors params
      Dataset.find(params[:training_dataset_id]).nanoparticles
    end

    def add_feature feature, value
      case feature.category
      when "P-CHEM"
        physchem_descriptors[feature.id.to_s] ||= []
        physchem_descriptors[feature.id.to_s] << value
        physchem_descriptors[feature.id.to_s].uniq!
      when "TOX"
        toxicities[feature.id.to_s] ||= []
        toxicities[feature.id.to_s] << value
        toxicities[feature.id.to_s].uniq!
      else
        warn "Unknown feature type '#{feature.category}'. Value '#{value}' not inserted."
      end
      save
    end

    def parse_ambit_value feature, v
      v.delete "unit"
      # TODO: mmol/log10 conversion
      if v.keys == ["textValue"]
        add_feature feature, v["textValue"]
      elsif v.keys == ["loValue"]
        add_feature feature, v["loValue"]
      elsif v.keys.size == 2 and v["errorValue"]
        add_feature feature, v["loValue"]
        warn "Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
      elsif v.keys.size == 2 and v["loQualifier"] == "mean"
        add_feature feature, v["loValue"]
        warn "'#{feature.name}' is a mean value. Original data is not available."
      elsif v.keys.size == 2 and v["loQualifier"] #== ">="
        warn "Only min value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 2 and v["upQualifier"] #== ">="
        warn "Only max value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 3 and v["loValue"] and v["loQualifier"].nil? and v["upQualifier"].nil?
        add_feature feature, v["loValue"]
        warn "loQualifier and upQualifier are empty."
      elsif v.keys.size == 3 and v["loValue"] and v["loQualifier"] == "" and v["upQualifier"] == ""
        add_feature feature, v["loValue"]
        warn "loQualifier and upQualifier are empty."
      elsif v.keys.size == 4 and v["loValue"] and v["loQualifier"].nil? and v["upQualifier"].nil?
        add_feature feature, v["loValue"]
        warn "loQualifier and upQualifier are empty."
      elsif v.size == 4 and v["loQualifier"] and v["upQualifier"] and v["loValue"] and v["upValue"]
        add_feature feature, [v["loValue"],v["upValue"]].mean
        warn "Using mean value of range #{v["loValue"]} - #{v["upValue"]} for '#{feature.name}'. Original data is not available."
      elsif v.size == 4 and v["loQualifier"] == "mean" and v["errorValue"]
        warn "'#{feature.name}' is a mean value. Original data is not available. Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
        add_feature feature, v["loValue"]
      elsif v == {} # do nothing
      else
        warn "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
      end
    end

  end
end


