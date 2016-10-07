module OpenTox
  module Algorithm
    
    class Regression

      def self.weighted_average descriptors:nil, neighbors:, parameters:nil, method:nil, relevant_features:nil
        # TODO: prediction_interval
        weighted_sum = 0.0
        sim_sum = 0.0
        neighbors.each do |neighbor|
          sim = neighbor["similarity"]
          activities = neighbor["measurements"]
          activities.each do |act|
            weighted_sum += sim*act
            sim_sum += sim
          end if activities
        end
        sim_sum == 0 ? prediction = nil : prediction = weighted_sum/sim_sum
        {:value => prediction}
      end

    end
  end
end

