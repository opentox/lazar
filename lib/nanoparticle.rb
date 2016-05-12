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
      p dataset.data_entries.size
      p dataset.substance_ids.size
      p dataset.substance_ids.collect{|i| i.to_s} == dataset.data_entries.keys
      p dataset.substance_ids.collect{|i| i.to_s} 
      p dataset.data_entries.keys
      dataset.nanoparticles.each do |np|
        prediction_feature_id
        p dataset.data_entries[np.id.to_s]
        values = dataset.values(np,prediction_feature_id)
        p values
        if values
          common_descriptors = physchem_descriptors.keys & np.physchem_descriptors.keys
          sim = Algorithm::Similarity.cosine(common_descriptors.collect{|d| physchem_descriptors[d]}, common_descriptors.collect{|d| np.physchem_descriptors[d]})
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
        p dataset.name
        p self.name
        p feature.name
        p feature.unit
        p value
        if feature.name == "7.99 Toxicity (other) ICP-AES" and feature.unit == "mL/ug(Mg)" 
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
        add_feature feature, [v["loValue"],v["upValue"]].mean, dataset
        #warn "Using mean value of range #{v["loValue"]} - #{v["upValue"]} for '#{feature.name}'. Original data is not available."
      elsif v.size == 4 and v["loQualifier"] == "mean" and v["errorValue"]
        #warn "'#{feature.name}' is a mean value. Original data is not available. Ignoring errorValue '#{v["errorValue"]}' for '#{feature.name}'."
        add_feature feature, v["loValue"], dataset
      elsif v == {} # do nothing
      else
        #warn "Cannot parse Ambit eNanoMapper value '#{v}' for feature '#{feature.name}'."
      end
    end

  end
end
