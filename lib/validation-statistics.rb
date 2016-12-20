module OpenTox
  module Validation
    module ClassificationStatistics

      def statistics 
        self.accept_values = model.prediction_feature.accept_values
        self.confusion_matrix = Array.new(accept_values.size){Array.new(accept_values.size,0)}
        self.weighted_confusion_matrix = Array.new(accept_values.size){Array.new(accept_values.size,0)}
        nr_instances = 0
        predictions.each do |cid,pred|
          # TODO
          # use predictions without probabilities (single neighbor)??
          # use measured majority class??
          if pred[:measurements].uniq.size == 1 and pred[:probabilities]
            m = pred[:measurements].first
            if pred[:value] == m
              if pred[:value] == accept_values[0]
                confusion_matrix[0][0] += 1
                weighted_confusion_matrix[0][0] += pred[:probabilities][pred[:value]]
                nr_instances += 1
              elsif pred[:value] == accept_values[1]
                confusion_matrix[1][1] += 1
                weighted_confusion_matrix[1][1] += pred[:probabilities][pred[:value]]
                nr_instances += 1
              end
            elsif pred[:value] != m
              if pred[:value] == accept_values[0]
                confusion_matrix[0][1] += 1
                weighted_confusion_matrix[0][1] += pred[:probabilities][pred[:value]]
                nr_instances += 1
              elsif pred[:value] == accept_values[1]
                confusion_matrix[1][0] += 1
                weighted_confusion_matrix[1][0] += pred[:probabilities][pred[:value]]
                nr_instances += 1
              end
            end
          end
        end
        self.true_rate = {}
        self.predictivity = {}
        accept_values.each_with_index do |v,i|
          self.true_rate[v] = confusion_matrix[i][i]/confusion_matrix[i].reduce(:+).to_f
          self.predictivity[v] = confusion_matrix[i][i]/confusion_matrix.collect{|n| n[i]}.reduce(:+).to_f
        end
        confidence_sum = 0
        weighted_confusion_matrix.each do |r|
          r.each do |c|
            confidence_sum += c
          end
        end
        self.accuracy = (confusion_matrix[0][0]+confusion_matrix[1][1])/nr_instances.to_f
        self.weighted_accuracy = (weighted_confusion_matrix[0][0]+weighted_confusion_matrix[1][1])/confidence_sum.to_f
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
        }
      end

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

    module RegressionStatistics

      def statistics
        self.rmse = 0
        self.mae = 0
        self.within_prediction_interval = 0
        self.out_of_prediction_interval = 0
        x = []
        y = []
        predictions.each do |cid,pred|
          if pred[:value] and pred[:measurements] 
            x << pred[:measurements].median
            y << pred[:value]
            error = pred[:value]-pred[:measurements].median
            self.rmse += error**2
            self.mae += error.abs
            if pred[:prediction_interval]
              if pred[:measurements].median >= pred[:prediction_interval][0] and pred[:measurements].median <= pred[:prediction_interval][1]
                self.within_prediction_interval += 1
              else
                self.out_of_prediction_interval += 1
              end
            end
          else
            warnings << "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
            $logger.debug "No training activities for #{Compound.find(compound_id).smiles} in training dataset #{model.training_dataset_id}."
          end
        end
        R.assign "measurement", x
        R.assign "prediction", y
        R.eval "r <- cor(measurement,prediction,use='pairwise')"
        self.r_squared = R.eval("r").to_ruby**2
        self.mae = self.mae/predictions.size
        self.rmse = Math.sqrt(self.rmse/predictions.size)
        $logger.debug "R^2 #{r_squared}"
        $logger.debug "RMSE #{rmse}"
        $logger.debug "MAE #{mae}"
        $logger.debug "#{percent_within_prediction_interval.round(2)}% of measurements within prediction interval"
        save
        {
          :mae => mae,
          :rmse => rmse,
          :r_squared => r_squared,
          :within_prediction_interval => within_prediction_interval,
          :out_of_prediction_interval => out_of_prediction_interval,
        }
      end

      def percent_within_prediction_interval
        100*within_prediction_interval.to_f/(within_prediction_interval+out_of_prediction_interval)
      end

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
          title = feature.name
          title += "[#{feature.unit}]" if feature.unit and !feature.unit.blank?
          R.eval "image = qplot(prediction,measurement,main='#{title}',xlab='Prediction',ylab='Measurement',asp=1,xlim=range, ylim=range)"
          R.eval "image = image + geom_abline(intercept=0, slope=1)"
          R.eval "ggsave(file='#{tmpfile}', plot=image)"
          file = Mongo::Grid::File.new(File.read(tmpfile), :filename => "#{id.to_s}_correlation_plot.#{format}")
          plot_id = $gridfs.insert_one(file)
          update(:correlation_plot_id => plot_id)
        end
        $gridfs.find_one(_id: correlation_plot_id).data
      end

      def worst_predictions n: 5, show_neigbors: true, show_common_descriptors: false
        worst_predictions = predictions.sort_by{|sid,p| -(p["value"] - p["measurements"].median).abs}[0,n]
        worst_predictions.collect do |p|
          substance = Substance.find(p.first)
          prediction = p[1]
          if show_neigbors
            neighbors = prediction["neighbors"].collect do |n|
              common_descriptors = []
              if show_common_descriptors
                common_descriptors = n["common_descriptors"].collect do |d|
                  f=Feature.find(d)
                  {
                    :id => f.id.to_s,
                    :name => "#{f.name} (#{f.conditions})",
                    :p_value => d[:p_value],
                    :r_squared => d[:r_squared],
                  }
                end
              else
                common_descriptors = n["common_descriptors"].size
              end
              {
                :name => Substance.find(n["_id"]).name,
                :id => n["_id"].to_s,
                :common_descriptors => common_descriptors
              }
            end
          else
            neighbors = prediction["neighbors"].size
          end
          {
            :id => substance.id.to_s,
            :name => substance.name,
            :feature => Feature.find(prediction["prediction_feature_id"]).name,
            :error => (prediction["value"] - prediction["measurements"].median).abs,
            :prediction => prediction["value"],
            :measurements => prediction["measurements"],
            :neighbors => neighbors
          }
        end
      end
    end
  end
end
