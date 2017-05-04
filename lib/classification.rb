module OpenTox
  module Algorithm
    
    # Classification algorithms
    class Classification

      # Weighted majority vote
      # @param [Array<TrueClass,FalseClass>] dependent_variables
      # @param [Array<Float>] weights
      # @return [Hash]
      def self.weighted_majority_vote dependent_variables:, independent_variables:nil, weights:, query_variables:nil
        class_weights = {}
        dependent_variables.each_with_index do |v,i|
          class_weights[v] ||= []
          class_weights[v] << weights[i] unless v.nil?
        end
        probabilities = {}
        class_weights.each do |a,w|
          probabilities[a] = w.sum/weights.sum
        end
        # DG: hack to ensure always two probability values
        if probabilities.keys.uniq.size == 1
          missing_key = probabilities.keys.uniq[0].match(/^non/) ? probabilities.keys.uniq[0].sub(/non-/,"") : "non-"+probabilities.keys.uniq[0]
          probabilities[missing_key] = 0.0
        end
        probabilities = probabilities.collect{|a,p| [a,weights.max*p]}.to_h
        p_max = probabilities.collect{|a,p| p}.max
        prediction = probabilities.key(p_max)
        {:value => prediction,:probabilities => probabilities}
      end

    end

  end
end

