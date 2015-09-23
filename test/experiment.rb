require_relative "setup.rb"

class ExperimentTest < MiniTest::Test

  def test_regression_experiment
    datasets = [
      "EPAFHM.medi.csv",
      #"EPAFHM.csv",
      #"FDA_v3b_Maximum_Recommended_Daily_Dose_mmol.csv",
      "LOAEL_mmol_corrected_smiles.csv"
    ]
    experiment = Experiment.create(
      :name => "Default regression for datasets #{datasets}.",
      :dataset_ids => datasets.collect{|d| Dataset.from_csv_file(File.join(DATA_DIR, d)).id},
      :model_settings => [
        {
          :algorithm => "OpenTox::Model::LazarRegression",
        }
      ]
    )
    #experiment.run
    puts experiment.report.to_yaml
    assert_equal datasets.size, experiment.results.size
    experiment.results.each do |dataset_id, result|
      assert_equal 1, result.size
      result.each do |r|
        assert_kind_of BSON::ObjectId, r[:model_id]
        assert_kind_of BSON::ObjectId, r[:repeated_crossvalidation_id]
      end
    end
  end

  def test_classification_experiment

    datasets = [ "hamster_carcinogenicity.csv" ]
    experiment = Experiment.create(
      :name => "Fminer vs fingerprint classification for datasets #{datasets}.",
      :dataset_ids => datasets.collect{|d| Dataset.from_csv_file(File.join(DATA_DIR, d)).id},
      :model_settings => [
        {
          :algorithm => "OpenTox::Model::LazarClassification",
        },{
          :algorithm => "OpenTox::Model::LazarClassification",
          :neighbor_algorithm_parameter => {:min_sim => 0.3}
        },
        #{
          #:algorithm => "OpenTox::Model::LazarFminerClassification",
        #}
      ]
    )
    #experiment.run
=begin
    experiment = Experiment.find "55f944a22b72ed7de2000000"
=end
    puts experiment.report.to_yaml
    experiment.results.each do |dataset_id, result|
      assert_equal 2, result.size
      result.each do |r|
        assert_kind_of BSON::ObjectId, r[:model_id]
        assert_kind_of BSON::ObjectId, r[:repeated_crossvalidation_id]
      end
    end
  end

  def test_regression_fingerprints
=begin
    datasets = [
      "EPAFHM.medi.csv",
      #"LOAEL_mmol_corrected_smiles.csv"
    ]
    min_sims = [0.3,0.7]
    #min_sims = [0.7]
    #types = ["FP2","FP3","FP4","MACCS","mpd"]
    types = ["mpd","FP3"]
    experiment = Experiment.create(
      :name => "Fingerprint regression with different types for datasets #{datasets}.",
      :dataset_ids => datasets.collect{|d| Dataset.from_csv_file(File.join(DATA_DIR, d)).id},
    )
    types.each do |type|
      min_sims.each do |min_sim|
        experiment.model_settings << {
          :model_algorithm => "OpenTox::Model::LazarRegression",
          :prediction_algorithm => "OpenTox::Algorithm::Regression.weighted_average",
          :neighbor_algorithm => "fingerprint_neighbors",
          :neighbor_algorithm_parameters => {
            :type => type,
            :min_sim => min_sim,
          }
        }
      end
    end
    experiment.run
=end
#=begin
    experiment = Experiment.find '56029cb92b72ed673d000000'
#=end
    p experiment.id
    experiment.results.each do |dataset,result|
      result.each do |r|
        params = Model::Lazar.find(r["model_id"])[:neighbor_algorithm_parameters]
        RepeatedCrossValidation.find(r["repeated_crossvalidation_id"]).crossvalidations.each do |cv|
          cv.validation_ids.each do |vid|
            model_params = Model::Lazar.find(Validation.find(vid).model_id)[:neighbor_algorithm_parameters]
            assert_equal params[:type], model_params[:type]
            assert_equal params[:min_sim], model_params[:min_sim]
            refute_equal params[:training_dataset_id], model_params[:training_dataset_id]
          end
        end
      end
    end
    puts experiment.report.to_yaml
    p experiment.summary
  end

  def test_mpd_fingerprints
=begin
    datasets = [
      "EPAFHM.medi.csv",
    ]
    types = ["FP2","mpd"]
    experiment = Experiment.create(
      :name => "FP2 vs mpd fingerprint regression for datasets #{datasets}.",
      :dataset_ids => datasets.collect{|d| Dataset.from_csv_file(File.join(DATA_DIR, d)).id},
    )
    types.each do |type|
    experiment.model_settings << {
      :algorithm => "OpenTox::Model::LazarRegression",
      :neighbor_algorithm => "fingerprint_neighbors",
      :neighbor_algorithm_parameter => {
        :type => type,
        :min_sim => 0.7,
      }
    }
    end
    experiment.run
    p experiment.id
=end
    experiment = Experiment.find '55ffd0c02b72ed123c000000'
    p experiment
    puts experiment.report.to_yaml
  end
end
