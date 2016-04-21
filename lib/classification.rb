module OpenTox
  module Algorithm
    
    class Classification

      def self.weighted_majority_vote compound, params
        neighbors = params[:neighbors]
        weighted_sum = {}
        sim_sum = 0.0
        confidence = 0.0
        # see ~/src/pubchem-read-across/application.rb:353
        neighbors.each do |row|
          sim = row["tanimoto"]
          row["toxicities"][params[:prediction_feature_id].to_s].each do |act|
            weighted_sum[act] ||= 0
            weighted_sum[act] += sim
          end
        end
        case weighted_sum.size
        when 1
          return {:value => weighted_sum.keys.first, :confidence => weighted_sum.values.first/neighbors.size.abs}
        when 2
          sim_sum = weighted_sum[weighted_sum.keys[0]]
          sim_sum -= weighted_sum[weighted_sum.keys[1]]
          sim_sum > 0 ? prediction = weighted_sum.keys[0] : prediction = weighted_sum.keys[1] 
          confidence = (sim_sum/neighbors.size).abs 
          return {:value => prediction,:confidence => confidence}
        else
          bad_request_error "Cannot predict more than 2 classes, multinomial classifications is not yet implemented. Received classes were: '#{weighted.sum.keys}'"
        end
      end
    end
  end
end

