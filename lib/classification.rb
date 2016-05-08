module OpenTox
  module Algorithm
    
    class Classification

      def self.weighted_majority_vote compound, params
        neighbors = params[:neighbors]
        feature_id = params[:prediction_feature_id].to_s
        dataset_id = params[:training_dataset_id].to_s
        sims = {}
        neighbors.each do |n|
          sim = n["tanimoto"]
          n["toxicities"][feature_id][dataset_id].each do |act|
            sims[act] ||= []
            sims[act] << sim
          end if n["toxicities"][feature_id][dataset_id]
        end
        sim_all = sims.collect{|a,s| s}.flatten
        sim_sum = sim_all.sum
        sim_max = sim_all.max
        probabilities = {}
        sims.each do |a,s|
          probabilities[a] = s.sum/sim_sum
        end
        probabilities = probabilities.collect{|a,p| [a,sim_max*p]}.to_h
        p_max = probabilities.collect{|a,p| p}.max
        prediction = probabilities.key(p_max)
        {:value => prediction,:probabilities => probabilities}

      end
    end
  end
end

