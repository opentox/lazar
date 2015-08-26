require_relative "setup.rb"

class ExperimentTest < MiniTest::Test

  def test_regression_experiment
    datasets = [
      "EPAFHM.csv",
      "FDA_v3b_Maximum_Recommended_Daily_Dose_mmol.csv",
      "LOAEL_mmol_corrected_smiles.csv"
      ]
    model_algorithms = ["OpenTox::Model::LazarRegression"]
    neighbor_algorithms = ["OpenTox::Algorithm::Neighbor.fingerprint_similarity"]
    prediction_algorithms = ["OpenTox::Algorithm::Regression.weighted_average"]
    neighbor_algorithm_parameters = [{:min_sim => 0.7}]
    experiment = Experiment.create(
      :name => "Regression for datasets #{datasets}.",
      :dataset_ids => datasets.collect{|d| Dataset.from_csv_file(File.join(DATA_DIR, d)).id},
      :model_algorithms => model_algorithms,
      :neighbor_algorithms => neighbor_algorithms,
      :neighbor_algorithm_parameters => neighbor_algorithm_parameters,
      :prediction_algorithms => prediction_algorithms,
    )
    experiment.run
    experiment = Experiment.find "55dda70d2b72ed6ea9000188"
=begin
    p experiment.id
=end
    experiment.report
    refute_empty experiment.crossvalidation_ids
  end
end
