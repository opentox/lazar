module OpenTox
  module Algorithm
    class Neighbor

      def self.fingerprint_similarity compound, params={}
        compound.neighbors params[:min_sim]
      end

      def self.fminer_similarity compound, params
        feature_dataset = Dataset.find params[:feature_dataset_id]
        query_fingerprint = Algorithm::Descriptor.smarts_match(compound, feature_dataset.features.collect{|f| f.smarts} )
        neighbors = []

        # find neighbors
        feature_dataset.data_entries.each_with_index do |fingerprint, i|
          sim = Algorithm::Similarity.tanimoto fingerprint, query_fingerprint
          if sim > params[:min_sim]
            neighbors << [feature_dataset.compound_ids[i],sim] # use compound_ids, instantiation of Compounds is too time consuming
          end
        end
        neighbors
      end
    end
  end
end
