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
      if feature.source.match /property\/P-CHEM/
        physchem_descriptors[feature.id.to_s] ||= []
        physchem_descriptors[feature.id.to_s] << value
      elsif feature.source.match /property\/TOX/
        toxicities[feature.id.to_s] ||= []
        toxicities[feature.id.to_s] << value
      else
        warn "Unknown feature type '#{feature.source}'. Value '#{value}' not inserted."
      end
    end

    def parse_ambit_value feature, v
      # TODO: units, mmol/log10 conversion
      if v.keys == ["loValue"]
        #if v["loValue"].numeric?
          add_feature feature, v["loValue"]
        #else
          #warn "'#{v["loValue"]}' is not a numeric value, entry ignored."
        #end
      elsif v.keys.size == 2 and v["loQualifier"] == "mean"
        #add_feature feature, {:mean => v["loValue"]}
        add_feature feature, v["loValue"]
        warn "'#{feature.name}' is a mean value. Original data is not available."
      elsif v.keys.size == 2 and v["loQualifier"] #== ">="
        #add_feature feature, {:min => v["loValue"],:max => Float::INFINITY}
        warn "Only min value available for '#{feature.name}', entry ignored"
      elsif v.keys.size == 2 and v["upQualifier"] #== ">="
        #add_feature feature, {:max => v["upValue"],:min => -Float::INFINITY}
        warn "Only max value available for '#{feature.name}', entry ignored"
      elsif v.size == 4 and v["loQualifier"] and v["upQualifier"] 
        #add_feature feature, {:min => v["loValue"],:max => v["upValue"]}
        add_feature feature, [v["loValue"],v["upValue"]].mean
        warn "Using mean value of range #{v["loValue"]} - #{v["upValue"]} for '#{feature.name}'. Original data is not available."
      elsif v == {} # do nothing
      else
        $logger.warn "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
        warnings << "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
      end
    end

  end
end


