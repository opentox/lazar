module OpenTox
  module Algorithm
    
    class Classification

      def self.weighted_majority_vote compound, params
        neighbors = params[:neighbors]
        feature_id = params[:prediction_feature_id].to_s
        sims = {}
        neighbors.each do |n|
          sim = n["tanimoto"]
          n["features"][feature_id].each do |act|
            sims[act] ||= []
            sims[act] << sim
            #sims[act] << 0.5*sim+0.5 # scale to 1-0.5 
          end
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

