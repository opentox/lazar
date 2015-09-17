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
    datasets = [
      "LOAEL_mmol_corrected_smiles.csv"
    ]
    min_sims = [0.3,0.7]
    types = ["FP2","FP3","FP4","MACCS"]
    experiment = Experiment.create(
      :name => "Fminer vs fingerprint classification for datasets #{datasets}.",
      :dataset_ids => datasets.collect{|d| Dataset.from_csv_file(File.join(DATA_DIR, d)).id},
    )
    types.each do |type|
      min_sims.each do |min_sim|
        experiment.model_settings << {
          :algorithm => "OpenTox::Model::LazarRegression",
          :neighbor_algorithm => "fingerprint_neighbors",
          :neighbor_algorithm_parameter => {
            :type => type,
            :min_sim => min_sim,
          }
        }
      end
    end
    experiment.run
    p experiment.report

  end
end
