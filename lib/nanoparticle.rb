module OpenTox

  class Nanoparticle < Substance
    include OpenTox

    field :core, type: Hash, default: {}
    field :coating, type: Array, default: []
    field :proteomics, type: Hash, default: {}

    attr_accessor :scaled_values
 
    def physchem_neighbors min_sim: 0.9, dataset_id:, prediction_feature_id:
      dataset = Dataset.find(dataset_id)
      relevant_features = {}
      measurements = []
      substances = []
      # TODO: exclude query activities!!!
      dataset.substances.each do |s|
        if s.core == self.core # exclude nanoparticles with different core
          dataset.values(s,prediction_feature_id).each do |act|
            measurements << act
            substances << s
          end
        end
      end
      R.assign "tox", measurements
      feature_ids = physchem_descriptors.keys.select{|fid| Feature.find(fid).is_a? NumericFeature}
      # identify relevant features
      feature_ids.each do |feature_id|
        feature_values = substances.collect{|s| s["physchem_descriptors"][feature_id].first if s["physchem_descriptors"][feature_id]}
        unless feature_values.uniq.size == 1
          R.assign "feature", feature_values
          begin
            R.eval "cor <- cor.test(tox,feature,method = 'pearson',use='pairwise')"
            p_value = R.eval("cor$p.value").to_ruby
            if p_value <= 0.05
              r = R.eval("cor$estimate").to_ruby
              relevant_features[feature_id] = {}
              relevant_features[feature_id]["p_value"] = p_value
              relevant_features[feature_id]["r"] = r
              relevant_features[feature_id]["mean"] = R.eval("mean(feature, na.rm=TRUE)").to_ruby
              relevant_features[feature_id]["sd"] = R.eval("sd(feature, na.rm=TRUE)").to_ruby
            end
          rescue
            warn "Correlation of '#{Feature.find(feature_id).name}' (#{feature_values}) with '#{Feature.find(prediction_feature_id).name}' (#{measurements}) failed."
          end
        end
      end
      neighbors = []
      substances.each do |substance|
        values = dataset.values(substance,prediction_feature_id)
        if values
          common_descriptors = relevant_features.keys & substance.physchem_descriptors.keys
          # scale values
          query_descriptors = common_descriptors.collect{|d| (physchem_descriptors[d].median-relevant_features[d]["mean"])/relevant_features[d]["sd"]}
          @scaled_values = common_descriptors.collect{|d| [d,(physchem_descriptors[d].median-relevant_features[d]["mean"])/relevant_features[d]["sd"]]}.to_h
          neighbor_descriptors = common_descriptors.collect{|d| (substance.physchem_descriptors[d].median-relevant_features[d]["mean"])/relevant_features[d]["sd"]}
          neighbor_scaled_values = common_descriptors.collect{|d| [d,(substance.physchem_descriptors[d].median-relevant_features[d]["mean"])/relevant_features[d]["sd"]]}.to_h
          #weights = common_descriptors.collect{|d| 1-relevant_features[d]["p_value"]}
          weights = common_descriptors.collect{|d| relevant_features[d]["r"]**2}
          sim = Algorithm::Similarity.weighted_cosine(query_descriptors,neighbor_descriptors,weights)
          neighbors << {
            "_id" => substance.id,
            "measurements" => values,
            "similarity" => sim,
            "common_descriptors" => common_descriptors.collect do |id|
              {
                :id => id,
                :scaled_value => neighbor_scaled_values[id],
                :p_value => relevant_features[id]["p_value"],
                :r_squared => relevant_features[id]["r"]**2}
            end
          } if sim >= min_sim
        end
      end
      $logger.debug "#{self.name}: #{neighbors.size} neighbors"
      neighbors.sort!{|a,b| b["similarity"] <=> a["similarity"]}
      neighbors
    end

    def add_feature feature, value, dataset
      unless feature.name == "ATOMIC COMPOSITION" or feature.name == "FUNCTIONAL GROUP" # redundand
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
          if feature.name == "Total protein (BCA assay)"
            physchem_descriptors[feature.id.to_s] ||= []
            physchem_descriptors[feature.id.to_s] << value
            physchem_descriptors[feature.id.to_s].uniq!
          else
            dataset.add self, feature, value
          end
          dataset.save
          dataset_ids << dataset.id
          dataset_ids.uniq!
        else
          warn "Unknown feature type '#{feature.category}'. Value '#{value}' not inserted."
        end
      end
    end

    def parse_ambit_value feature, v, dataset
      #p dataset
      #p feature
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
