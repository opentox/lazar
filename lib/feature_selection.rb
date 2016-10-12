module OpenTox
  module Algorithm
    
    class FeatureSelection

      def self.correlation_filter model
        relevant_features = {}
        R.assign "dependent", model.dependent_variables.collect{|v| to_r(v)}
        model.descriptor_weights = []
        selected_variables = []
        selected_descriptor_ids = []
        model.independent_variables.each_with_index do |v,i|
          R.assign "independent", v.collect{|n| to_r(n)}
          begin
            R.eval "cor <- cor.test(dependent,independent,method = 'pearson',use='pairwise')"
            pvalue = R.eval("cor$p.value").to_ruby
            if pvalue <= 0.05
              model.descriptor_weights << R.eval("cor$estimate").to_ruby**2
              selected_variables << v
              selected_descriptor_ids << model.descriptor_ids[i]
            end
          rescue
            #warn "Correlation of '#{model.prediction_feature.name}' (#{model.dependent_variables}) with '#{Feature.find(model.descriptor_ids[i]).name}' (#{v}) failed."
            warn "Correlation of '#{model.prediction_feature.name}' (#{model.dependent_variables}) with (#{v}) failed."
          end
        end

        model.independent_variables = selected_variables
        model.descriptor_ids = selected_descriptor_ids
        model
      end

      def self.to_r v
        return 0 if v == false
        return 1 if v == true
        return "NA" if v.nil? 
        return "NA" if v.is_a? Float and v.nan?
        v
      end

    end

  end
end
