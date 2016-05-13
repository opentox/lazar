module OpenTox

  class Nanoparticle < Substance
    include OpenTox

    field :core, type: String
    field :coating, type: Array, default: []
    field :bundles, type: Array, default: []
    field :proteomics, type: Hash, default: {}

    def nanoparticle_neighbors min_sim: 0.1, type:, dataset_id:, prediction_feature_id:
      dataset = Dataset.find(dataset_id)
      neighbors = []
      dataset.nanoparticles.each do |np|
        values = dataset.values(np,prediction_feature_id)
        if values
          common_descriptors = physchem_descriptors.keys & np.physchem_descriptors.keys
          common_descriptors.select!{|id| NumericFeature.find(id) }
          query_descriptors = common_descriptors.collect{|d| physchem_descriptors[d].first}
          neighbor_descriptors = common_descriptors.collect{|d| np.physchem_descriptors[d].first}
          sim = Algorithm::Similarity.cosine(query_descriptors,neighbor_descriptors)
          neighbors << {"_id" => np.id, "toxicities" => values, "similarity" => sim} if sim >= min_sim
        end
      end
      neighbors.sort!{|a,b| b["similarity"] <=> a["similarity"]}
      neighbors
    end

    def add_feature feature, value, dataset_id
      dataset = Dataset.find(dataset_id)
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
        # TODO generic way of parsing TOX values
        if feature.name == "Net cell association" and feature.unit == "mL/ug(Mg)" 
          dataset.add self, feature, -Math.log10(value)
        else
          dataset.add self, feature, value
        end
        dataset.save
      else
        warn "Unknown feature type '#{feature.category}'. Value '#{value}' not inserted."
      end
    end

    def parse_ambit_value feature, v, dataset_id
      dataset = Dataset.find(dataset_id)
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
