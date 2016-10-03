module OpenTox
  module Algorithm
    
    class Classification

      def self.weighted_majority_vote substance:, neighbors:
        sims = {}
        neighbors.each do |neighbor|
          sim = neighbor["similarity"]
          activities = neighbor["measurements"]
          activities.each do |act|
            sims[act] ||= []
            sims[act] << sim
          end if activities
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

