module OpenTox
  module Algorithm
    
    # Regression algorithms
    class Regression

      # Weighted average
      # @param [Array<TrueClass,FalseClass>] dependent_variables
      # @param [Array<Float>] weights
      # @return [Hash]
      def self.weighted_average dependent_variables:, independent_variables:nil, weights:, query_variables:nil
        # TODO: prediction_interval
        weighted_sum = 0.0
        sim_sum = 0.0
        dependent_variables.each_with_index do |v,i|
          weighted_sum += weights[i]*dependent_variables[i]
          sim_sum += weights[i]
        end if dependent_variables
        sim_sum == 0 ? prediction = nil : prediction = weighted_sum/sim_sum
        {:value => prediction}
      end

    end
  end
end

