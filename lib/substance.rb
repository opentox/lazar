module OpenTox

  class Substance
    field :properties, type: Hash, default: {}
    field :dataset_ids, type: Array, default: []
  end

  def neighbors dataset_id:,prediction_feature_id:,descriptors:,similarity:,relevant_features:nil
    # TODO enable empty dataset_id -> use complete db
    case descriptors[:method]
    when "fingerprint"
      fingerprint_neighbors dataset_id:dataset_id, prediction_feature_id:prediction_feature_id, descriptors:descriptors, similarity:similarity
    when "properties"
      properties_neighbors dataset_id:dataset_id, prediction_feature_id:prediction_feature_id, descriptors:descriptors, similarity:similarity, relevant_features: relevant_features
    else
      bad_request_error "Descriptor method '#{descriptors[:method]}' not implemented."
    end
  end

  def fingerprint_neighbors dataset_id:,prediction_feature_id:,descriptors:,similarity:
    neighbors = []
    dataset = Dataset.find(dataset_id)
    dataset.substances.each do |substance|
      values = dataset.values(substance,prediction_feature_id)
      if values
        query_descriptors = self.send(descriptors[:method].to_sym, descriptors[:type])
        candidate_descriptors = substance.send(descriptors[:method].to_sym, descriptors[:type])
        sim = Algorithm.run similarity[:method], [query_descriptors, candidate_descriptors]
        neighbors << {"_id" => substance.id, "measurements" => values, "descriptors" => candidate_descriptors, "similarity" => sim} if sim >= similarity[:min]
      end
    end
    neighbors.sort{|a,b| b["similarity"] <=> a["similarity"]}
  end

  def properties_neighbors dataset_id:,prediction_feature_id:,descriptors:,similarity:,relevant_features:
    neighbors = []
    dataset = Dataset.find(dataset_id)
    weights = relevant_features.collect{|k,v| v["r"]**2}
    means = relevant_features.collect{|k,v| v["mean"]}
    standard_deviations = relevant_features.collect{|k,v| v["sd"]}
    query_descriptors = relevant_features.keys.collect{|i| properties[i].is_a?(Array) ? properties[i].median : nil  }
    dataset.substances.each do |substance|
      values = dataset.values(substance,prediction_feature_id)
      # exclude nanoparticles with different core
      # TODO validate exclusion
      next if substance.is_a? Nanoparticle and substance.core != self.core
      if values
        candidate_descriptors = relevant_features.keys.collect{|i| substance.properties[i].is_a?(Array) ? substance.properties[i].median : nil  }
        q = []
        c = []
        w = []
        (0..relevant_features.size-1).each do |i|
          # add only complete pairs
          if query_descriptors[i] and candidate_descriptors[i]
            w << weights[i]
            # scale values
            q << (query_descriptors[i] - means[i])/standard_deviations[i]
            c << (candidate_descriptors[i] - means[i])/standard_deviations[i]
          end
        end
        sim = Algorithm.run similarity[:method], [q, c, w]
        neighbors << {"_id" => substance.id, "measurements" => values, "descriptors" => candidate_descriptors, "similarity" => sim} if sim >= similarity[:min]
      end
    end
    neighbors.sort{|a,b| b["similarity"] <=> a["similarity"]}
  end

end
