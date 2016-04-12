module OpenTox

  class Nanoparticle < Substance
    include OpenTox

    field :core, type: String
    field :coating, type: Array, default: []

    field :physchem_descriptors, type: Hash, default: {}
    field :toxicities, type: Hash, default: {}
    #field :features, type: Hash, default: {}
    field :bundles, type: Array, default: []

    def predict
    end

    def add_feature feature, value
      if feature.source.match /property\/P-CHEM/
        physchem_descriptors[feature.id.to_s] ||= []
        physchem_descriptors[feature.id.to_s] << value
      elsif feature.source.match /property\/TOX/
        toxicities[feature.id.to_s] ||= []
        toxicities[feature.id.to_s] << value
      else
        $logger.warn "Unknown feature type '#{feature.source}'. Value '#{value}' not inserted."
        warnings << "Unknown feature type '#{feature.source}'. Value '#{value}' not inserted."
      end
    end

    def parse_ambit_value feature, v
      if v.keys == ["loValue"]
        add_feature feature, v["loValue"]
      elsif v.keys.size == 2 and v["loQualifier"] == "mean"
        add_feature feature, {:mean => v["loValue"]}
      elsif v.keys.size == 2 and v["loQualifier"] #== ">="
        add_feature feature, {:min => v["loValue"],:max => Float::INFINITY}
      elsif v.keys.size == 2 and v["upQualifier"] #== ">="
        add_feature feature, {:max => v["upValue"],:min => -Float::INFINITY}
      elsif v.size == 4 and v["loQualifier"] and v["upQualifier"] 
        add_feature feature, {:min => v["loValue"],:max => v["upValue"]}
      elsif v == {} # do nothing
      else
        $logger.warn "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
        warnings << "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
      end
    end

  end
end


