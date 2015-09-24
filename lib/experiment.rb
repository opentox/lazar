module OpenTox

  class Experiment
    field :dataset_ids, type: Array
    field :model_settings, type: Array, default: []
    field :results, type: Hash, default: {}

    def run 
      dataset_ids.each do |dataset_id|
        dataset = Dataset.find(dataset_id)
        results[dataset_id.to_s] = []
        model_settings.each do |setting|
          setting = setting.dup
          model_algorithm = setting.delete :model_algorithm #if setting[:model_algorithm]
          model = Object.const_get(model_algorithm).create dataset, setting
          $logger.debug model
          model.save
          repeated_crossvalidation = RepeatedCrossValidation.create model
          results[dataset_id.to_s] << {:model_id => model.id, :repeated_crossvalidation_id => repeated_crossvalidation.id}
        end
      end
      save
    end

    def report
      # statistical significances http://www.r-bloggers.com/anova-and-tukeys-test-on-r/
      report = {}
      report[:name] = name
      report[:experiment_id] = self.id.to_s
      report[:results] = {}
      parameters = []
      dataset_ids.each do |dataset_id|
        dataset_name = Dataset.find(dataset_id).name
        report[:results][dataset_name] = {}
        report[:results][dataset_name][:anova] = {}
        report[:results][dataset_name][:data] = []
        results[dataset_id.to_s].each do |result|
          model = Model::Lazar.find(result[:model_id])
          repeated_cv = RepeatedCrossValidation.find(result[:repeated_crossvalidation_id])
          crossvalidations = repeated_cv.crossvalidations
          if crossvalidations.first.is_a? ClassificationCrossValidation
            parameters = [:accuracy,:true_rate,:predictivity]
          elsif crossvalidations.first.is_a? RegressionCrossValidation
            parameters = [:rmse,:mae,:r_squared]
          end
          summary = {}
          [:neighbor_algorithm, :neighbor_algorithm_parameters, :prediction_algorithm].each do |key|
            summary[key] = model[key]
          end
          summary[:nr_instances] = crossvalidations.first.nr_instances
          summary[:nr_unpredicted] = crossvalidations.collect{|cv| cv.nr_unpredicted}
          summary[:time] = crossvalidations.collect{|cv| cv.time}
          parameters.each do |param|
            summary[param] = crossvalidations.collect{|cv| cv.send(param)}
          end
          report[:results][dataset_name][:data] << summary
        end
      end
      report[:results].each do |dataset,results|
        ([:time,:nr_unpredicted]+parameters).each do |param|
          experiments = []
          outcome = []
          results[:data].each_with_index do |result,i|
            result[param].each do |p|
              experiments << i
              p = nil if p.kind_of? Float and p.infinite? # TODO fix @ division by 0
              outcome << p
            end
          end
          R.assign "experiment_nr",experiments.collect{|i| "Experiment #{i}"}
          R.eval "experiment_nr = factor(experiment_nr)"
          R.assign "outcome", outcome
          R.eval "data = data.frame(experiment_nr,outcome)"
          # one-way ANOVA
          R.eval "fit = aov(outcome ~ experiment_nr, data=data,na.action='na.omit')"
          # http://stackoverflow.com/questions/3366506/extract-p-value-from-aov
          p_value = R.eval("summary(fit)[[1]][['Pr(>F)']][[1]]").to_ruby
          # aequivalent
          # sum = R.eval("summary(fit)")
          #p_value = sum.to_ruby.first.last.first
          report[:results][dataset][:anova][param] = p_value
=begin
=end
        end
      end
      report
    end

    def summary
      report[:results].collect{|dataset,data| {dataset => data[:anova].select{|param,p_val| p_val < 0.1}}}
    end
  end

end
