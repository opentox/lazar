module OpenTox
  module Validation
    # Statistical evaluation of classification validations
    module ClassificationStatistics

      # Get statistics
      # @return [Hash]
      def statistics 
        self.accept_values = model.prediction_feature.accept_values
        self.confusion_matrix = {:all => Array.new(accept_values.size){Array.new(accept_values.size,0)}, :without_warnings => Array.new(accept_values.size){Array.new(accept_values.size,0)}}
        self.weighted_confusion_matrix = {:all => Array.new(accept_values.size){Array.new(accept_values.size,0)}, :without_warnings => Array.new(accept_values.size){Array.new(accept_values.size,0)}}
        self.nr_predictions = {:all => 0,:without_warnings => 0}
        predictions.each do |cid,pred|
          # TODO
          # use predictions without probabilities (single neighbor)??
          # use measured majority class??
          if pred[:measurements].uniq.size == 1 and pred[:probabilities]
            m = pred[:measurements].first
            if pred[:value] == m
              if pred[:value] == accept_values[0]
                confusion_matrix[:all][0][0] += 1
                weighted_confusion_matrix[:all][0][0] += pred[:probabilities][pred[:value]]
                self.nr_predictions[:all] += 1
                if pred[:warnings].empty?
                  confusion_matrix[:without_warnings][0][0] += 1
                  weighted_confusion_matrix[:without_warnings][0][0] += pred[:probabilities][pred[:value]]
                  self.nr_predictions[:without_warnings] += 1
                end
              elsif pred[:value] == accept_values[1]
                confusion_matrix[:all][1][1] += 1
                weighted_confusion_matrix[:all][1][1] += pred[:probabilities][pred[:value]]
                self.nr_predictions[:all] += 1
                if pred[:warnings].empty?
                  confusion_matrix[:without_warnings][1][1] += 1
                  weighted_confusion_matrix[:without_warnings][1][1] += pred[:probabilities][pred[:value]]
                  self.nr_predictions[:without_warnings] += 1
                end
              end
            elsif pred[:value] != m
              if pred[:value] == accept_values[0]
                confusion_matrix[:all][0][1] += 1
                weighted_confusion_matrix[:all][0][1] += pred[:probabilities][pred[:value]]
                self.nr_predictions[:all] += 1
                if pred[:warnings].empty?
                  confusion_matrix[:without_warnings][0][1] += 1
                  weighted_confusion_matrix[:without_warnings][0][1] += pred[:probabilities][pred[:value]]
                  self.nr_predictions[:without_warnings] += 1
                end
              elsif pred[:value] == accept_values[1]
                confusion_matrix[:all][1][0] += 1
                weighted_confusion_matrix[:all][1][0] += pred[:probabilities][pred[:value]]
                self.nr_predictions[:all] += 1
                if pred[:warnings].empty?
                  confusion_matrix[:without_warnings][1][0] += 1
                  weighted_confusion_matrix[:without_warnings][1][0] += pred[:probabilities][pred[:value]]
                  self.nr_predictions[:without_warnings] += 1
                end
              end
            end
          end
        end
        self.true_rate = {:all => {}, :without_warnings => {}}
        self.predictivity = {:all => {}, :without_warnings => {}}
        accept_values.each_with_index do |v,i|
          [:all,:without_warnings].each do |a|
            self.true_rate[a][v] = confusion_matrix[a][i][i]/confusion_matrix[a][i].reduce(:+).to_f
            self.predictivity[a][v] = confusion_matrix[a][i][i]/confusion_matrix[a].collect{|n| n[i]}.reduce(:+).to_f
          end
        end
        confidence_sum = {:all => 0, :without_warnings => 0}
        [:all,:without_warnings].each do |a|
          weighted_confusion_matrix[a].each do |r|
            r.each do |c|
              confidence_sum[a] += c
            end
          end
        end
        self.accuracy = {}
        self.weighted_accuracy = {}
        [:all,:without_warnings].each do |a|
          self.accuracy[a] = (confusion_matrix[a][0][0]+confusion_matrix[a][1][1])/nr_predictions[a].to_f
          self.weighted_accuracy[a] = (weighted_confusion_matrix[a][0][0]+weighted_confusion_matrix[a][1][1])/confidence_sum[a].to_f
        end
        $logger.debug "Accuracy #{accuracy}"
        save
        {
          :accept_values => accept_values,
          :confusion_matrix => confusion_matrix,
          :weighted_confusion_matrix => weighted_confusion_matrix,
          :accuracy => accuracy,
          :weighted_accuracy => weighted_accuracy,
          :true_rate => self.true_rate,
          :predictivity => self.predictivity,
          :nr_predictions => nr_predictions,
        }
      end

      # Plot accuracy vs prediction probability
      # @param [String,nil] format
      # @return [Blob]
      def probability_plot format: "pdf"
        #unless probability_plot_id

          #tmpdir = File.join(ENV["HOME"], "tmp")
          tmpdir = "/tmp"
          #p tmpdir
          FileUtils.mkdir_p tmpdir
          tmpfile = File.join(tmpdir,"#{id.to_s}_probability.#{format}")
          accuracies = []
          probabilities = []
          correct_predictions = 0
          incorrect_predictions = 0
          pp = []
          predictions.values.select{|p| p["probabilities"]}.compact.each do |p|
            p["measurements"].each do |m|
              pp << [ p["probabilities"][p["value"]], p["value"] == m ]
            end
          end
          pp.sort_by!{|p| 1-p.first}
          pp.each do |p|
            p[1] ? correct_predictions += 1 : incorrect_predictions += 1
            accuracies << correct_predictions/(correct_predictions+incorrect_predictions).to_f
            probabilities << p[0]
          end
          R.assign "accuracy", accuracies
          R.assign "probability", probabilities
          R.eval "image = qplot(probability,accuracy)+ylab('Accumulated accuracy')+xlab('Prediction probability')+ylim(c(0,1))+scale_x_reverse()+geom_line()"
          R.eval "ggsave(file='#{tmpfile}', plot=image)"
          file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{self.id.to_s}_probability_plot.svg")
          plot_id = $gridfs.insert_one(file)
          update(:probability_plot_id => plot_id)
        #end
        $gridfs.find_one(_id: probability_plot_id).data
      end
    end

    # Statistical evaluation of regression validations
    module RegressionStatistics

      # Get statistics
      # @return [Hash]
      def statistics
        self.warnings = []
        self.rmse = {:all =>0,:without_warnings => 0}
        self.r_squared  = {:all =>0,:without_warnings => 0}
        self.mae = {:all =>0,:without_warnings => 0}
        self.within_prediction_interval = {:all =>0,:without_warnings => 0}
        self.out_of_prediction_interval = {:all =>0,:without_warnings => 0}
        x = {:all => [],:without_warnings => []}
        y = {:all => [],:without_warnings => []}
        self.nr_predictions = {:all =>0,:without_warnings => 0}
        predictions.each do |cid,pred|
          !if pred[:value] and pred[:measurements] and !pred[:measurements].empty?
            self.nr_predictions[:all] +=1
            x[:all] << pred[:measurements].median
            y[:all] << pred[:value]
            error = pred[:value]-pred[:measurements].median
            self.rmse[:all] += error**2
            self.mae[:all] += error.abs
            if pred[:prediction_interval]
              if pred[:measurements].median >= pred[:prediction_interval][0] and pred[:measurements].median <= pred[:prediction_interval][1]
                self.within_prediction_interval[:all] += 1
              else
                self.out_of_prediction_interval[:all] += 1
              end
            end
            if pred[:warnings].empty?
              self.nr_predictions[:without_warnings] +=1
              x[:without_warnings] << pred[:measurements].median
              y[:without_warnings] << pred[:value]
              error = pred[:value]-pred[:measurements].median
              self.rmse[:without_warnings] += error**2
              self.mae[:without_warnings] += error.abs
              if pred[:prediction_interval]
                if pred[:measurements].median >= pred[:prediction_interval][0] and pred[:measurements].median <= pred[:prediction_interval][1]
                  self.within_prediction_interval[:without_warnings] += 1
                else
                  self.out_of_prediction_interval[:without_warnings] += 1
                end
              end
            end
          else
            trd_id = model.training_dataset_id
            smiles = Compound.find(cid).smiles
            self.warnings << "No training activities for #{smiles} in training dataset #{trd_id}."
            $logger.debug "No training activities for #{smiles} in training dataset #{trd_id}."
          end
        end
        [:all,:without_warnings].each do |a|
          if x[a].size > 2
            R.assign "measurement", x[a]
            R.assign "prediction", y[a]
            R.eval "r <- cor(measurement,prediction,use='pairwise')"
            self.r_squared[a] = R.eval("r").to_ruby**2
          else
            self.r_squared[a] = 0
          end
          if self.nr_predictions[a] > 0
            self.mae[a] = self.mae[a]/self.nr_predictions[a]
            self.rmse[a] = Math.sqrt(self.rmse[a]/self.nr_predictions[a])
          else
            self.mae[a] = nil
            self.rmse[a] = nil
          end
        end
        $logger.debug "R^2 #{r_squared}"
        $logger.debug "RMSE #{rmse}"
        $logger.debug "MAE #{mae}"
        $logger.debug "Nr predictions #{nr_predictions}"
        $logger.debug "#{within_prediction_interval} measurements within prediction interval"
        $logger.debug "#{warnings}"
        save
        {
          :mae => mae,
          :rmse => rmse,
          :r_squared => r_squared,
          :within_prediction_interval => self.within_prediction_interval,
          :out_of_prediction_interval => out_of_prediction_interval,
          :nr_predictions => nr_predictions,
        }
      end

      # Plot predicted vs measured values
      # @param [String,nil] format
      # @return [Blob]
      def correlation_plot format: "png"
        unless correlation_plot_id
          tmpfile = "/tmp/#{id.to_s}_correlation.#{format}"
          x = []
          y = []
          feature = Feature.find(predictions.first.last["prediction_feature_id"])
          predictions.each do |sid,p|
            x << p["measurements"].median
            y << p["value"]
          end
          R.assign "measurement", x
          R.assign "prediction", y
          R.eval "all = c(measurement,prediction)"
          R.eval "range = c(min(all), max(all))"
          if feature.name.match /Net cell association/ # ad hoc fix for awkward units
            title = "log2(Net cell association [mL/ug(Mg)])"
          else
            title = feature.name
            title += " [#{feature.unit}]" if feature.unit and !feature.unit.blank?
          end
          R.eval "image = qplot(prediction,measurement,main='#{title}',xlab='Prediction',ylab='Measurement',asp=1,xlim=range, ylim=range)"
          R.eval "image = image + geom_abline(intercept=0, slope=1)"
          R.eval "ggsave(file='#{tmpfile}', plot=image)"
          file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{id.to_s}_correlation_plot.#{format}")
          plot_id = $gridfs.insert_one(file)
          update(:correlation_plot_id => plot_id)
        end
        $gridfs.find_one(_id: correlation_plot_id).data
      end

      # Get predictions with measurements outside of the prediction interval
      # @return [Hash]
      def worst_predictions
        worst_predictions = predictions.select do |sid,p|
          p["prediction_interval"] and p["value"] and (p["measurements"].max < p["prediction_interval"][0] or p["measurements"].min > p["prediction_interval"][1])
        end.compact.to_h
        worst_predictions.each do |sid,p|
          p["error"] = (p["value"] - p["measurements"].median).abs
          if p["measurements"].max < p["prediction_interval"][0]
            p["distance_prediction_interval"] = (p["measurements"].max - p["prediction_interval"][0]).abs
          elsif p["measurements"].min > p["prediction_interval"][1]
            p["distance_prediction_interval"] = (p["measurements"].min - p["prediction_interval"][1]).abs
          end
        end
        worst_predictions.sort_by{|sid,p| p["distance_prediction_interval"] }.to_h
      end
    end
  end
end
