module OpenTox
  module Algorithm
    
    class FeatureSelection

      def self.correlation_filter dataset:, prediction_feature:, types:nil
        # TODO: speedup, single assignment of all features to R+ parallel computation of significance?
        relevant_features = {}
        measurements = []
        substances = []
        dataset.substances.each do |s|
          dataset.values(s,prediction_feature).each do |act|
            measurements << act
            substances << s
          end
        end
        R.assign "tox", measurements
        feature_ids = dataset.substances.collect{ |s| s["properties"].keys}.flatten.uniq
        feature_ids.select!{|fid| types.include? Feature.find(fid).category} if types
        feature_ids.each do |feature_id|
          feature_values = substances.collect{|s| s["properties"][feature_id].first if s["properties"][feature_id]}
          unless feature_values.uniq.size == 1
            R.assign "feature", feature_values
            begin
              R.eval "cor <- cor.test(tox,feature,method = 'pearson',use='pairwise')"
              pvalue = R.eval("cor$p.value").to_ruby
              if pvalue <= 0.05
                r = R.eval("cor$estimate").to_ruby
                relevant_features[feature_id] = {}
                relevant_features[feature_id]["pvalue"] = pvalue
                relevant_features[feature_id]["r"] = r
                relevant_features[feature_id]["mean"] = R.eval("mean(feature, na.rm=TRUE)").to_ruby
                relevant_features[feature_id]["sd"] = R.eval("sd(feature, na.rm=TRUE)").to_ruby
              end
            rescue
              warn "Correlation of '#{Feature.find(feature_id).name}' (#{feature_values}) with '#{Feature.find(prediction_feature_id).name}' (#{measurements}) failed."
            end
          end
        end
        relevant_features.sort{|a,b| a[1]["pvalue"] <=> b[1]["pvalue"]}.to_h
      end

    end

  end
end
