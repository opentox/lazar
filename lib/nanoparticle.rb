module OpenTox

  class Nanoparticle < Substance
    include OpenTox

    field :core, type: Hash, default: {}
    field :coating, type: Array, default: []

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
          dataset.add self, feature, value
        else
          warn "Unknown feature type '#{feature.category}'. Value '#{value}' not inserted."
        end
        dataset_ids << dataset.id
        dataset_ids.uniq!
      end
    end

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
        warn "Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
      elsif v.keys.size == 2 and v["loQualifier"] == "mean"
        add_feature feature, v["loValue"], dataset
        warn "'#{feature.name}' is a mean value. Original data is not available."
      elsif v.keys.size == 2 and v["loQualifier"] #== ">="
        warn "Only min value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 2 and v["upQualifier"] #== ">="
        warn "Only max value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 3 and v["loValue"] and v["loQualifier"].nil? and v["upQualifier"].nil?
        add_feature feature, v["loValue"], dataset
        warn "loQualifier and upQualifier are empty."
      elsif v.keys.size == 3 and v["loValue"] and v["loQualifier"] == "" and v["upQualifier"] == ""
        add_feature feature, v["loValue"], dataset
        warn "loQualifier and upQualifier are empty."
      elsif v.keys.size == 4 and v["loValue"] and v["loQualifier"].nil? and v["upQualifier"].nil?
        add_feature feature, v["loValue"], dataset
        warn "loQualifier and upQualifier are empty."
      elsif v.size == 4 and v["loQualifier"] and v["upQualifier"] and v["loValue"] and v["upValue"]
        add_feature feature, [v["loValue"],v["upValue"]].mean, dataset
        warn "Using mean value of range #{v["loValue"]} - #{v["upValue"]} for '#{feature.name}'. Original data is not available."
      elsif v.size == 4 and v["loQualifier"] == "mean" and v["errorValue"]
        warn "'#{feature.name}' is a mean value. Original data is not available. Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
        add_feature feature, v["loValue"], dataset
      elsif v == {} # do nothing
      else
        warn "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
      end
    end

  end
end
