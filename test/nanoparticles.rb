require_relative "setup.rb"


class NanoparticleTest  < MiniTest::Test
  include OpenTox::Validation

  def setup
    #Import::Enanomapper.import File.join(File.dirname(__FILE__),"data","enm")
  end

  def test_create_model_with_feature_selection
    skip
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "Net cell association", category: "TOX", unit: "mL/ug(Mg)")
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_weighted_average", :neighbor_algorithm => "physchem_neighbors", :feature_selection_algorithm => "correlation_filter"})
    nanoparticle = training_dataset.nanoparticles[-34]
    #p nanoparticle.neighbors
    prediction = model.predict nanoparticle
    p prediction
    #p prediction
    refute_nil prediction[:value]
  end

  def test_create_model
    skip
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "Net cell association", category: "TOX", unit: "mL/ug(Mg)")
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_weighted_average", :neighbor_algorithm => "physchem_neighbors"})
    nanoparticle = training_dataset.nanoparticles[-34]
    prediction = model.predict nanoparticle
    refute_nil prediction[:value]
    assert_includes nanoparticle.dataset_ids, training_dataset.id
    model.delete
  end

  # TODO move to validation-statistics
  def test_inspect_cv
    skip
    cv = CrossValidation.all.sort_by{|cv| cv.created_at}.last
    cv.correlation_plot_id = nil
    File.open("tmp.pdf","w+"){|f| f.puts cv.correlation_plot}
    #p cv
=begin
    #File.open("tmp.pdf","w+"){|f| f.puts cv.correlation_plot}
    cv.predictions.sort_by{|sid,p| -(p["value"] - p["measurements"].median).abs}[0,5].each do |sid,p|
      s = Substance.find(sid)
      puts
      p s.name
      p([p["value"],p["measurements"],(p["value"]-p["measured"].median).abs])
      neighbors = s.physchem_neighbors dataset_id: cv.model.training_dataset_id, prediction_feature_id: cv.model.prediction_feature_id, type: nil
      neighbors.each do |n|
        neighbor = Substance.find(n["_id"])
        p "=="
        p neighbor.name, n["similarity"], n["measurements"]
        p neighbor.core["name"]
        p neighbor.coating.collect{|c| c["name"]}
        n["common_descriptors"].each do |id|
          f = Feature.find(id)
          print "#{f.name} #{f.conditions["MEDIUM"]}"
          print ", "
        end
        puts
      end

    end
=end
  end
  def test_inspect_worst_prediction
    skip
# TODO check/fix single/double neighbor prediction
    cv = CrossValidation.all.sort_by{|cv| cv.created_at}.last
    worst_predictions = cv.worst_predictions(n: 3,show_neigbors: false)
    assert_equal 3, worst_predictions.size
    assert_kind_of Integer, worst_predictions.first[:neighbors]
    worst_predictions = cv.worst_predictions
    #puts worst_predictions.to_yaml
    assert_equal 5, worst_predictions.size
    assert_kind_of Array, worst_predictions.first[:neighbors]
    assert_kind_of Integer, worst_predictions.first[:neighbors].first[:common_descriptors]
    worst_predictions = cv.worst_predictions(n: 2, show_common_descriptors: true)
    puts worst_predictions.to_yaml
    assert_equal 2, worst_predictions.size
    assert_kind_of Array, worst_predictions.first[:neighbors]
    refute_nil worst_predictions.first[:neighbors].first[:common_descriptors]
    #p cv.model.training_dataset.features
  end

  def test_validate_model
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    #feature = Feature.find_or_create_by(name: "Net cell association", category: "TOX", unit: "mL/ug(Mg)")
    feature = Feature.find_or_create_by(name: "Log2 transformed", category: "TOX")
    
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_weighted_average", :neighbor_algorithm => "physchem_neighbors", :neighbor_algorithm_parameters => {:min_sim => 0.5}})
    cv = RegressionCrossValidation.create model
    p cv
    #p cv.predictions.sort_by{|sid,p| (p["value"] - p["measurements"].median).abs}
    p cv.rmse
    p cv.r_squared
    #File.open("tmp.pdf","w+"){|f| f.puts cv.correlation_plot}
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_pls_model
    skip
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "Net cell association", category: "TOX", unit: "mL/ug(Mg)")
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression", :neighbor_algorithm => "physchem_neighbors"})
    cv = Validation::RegressionCrossValidation.create model
    p cv
    File.open("tmp.png","w+"){|f| f.puts cv.correlation_plot}
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_export
    skip
    Dataset.all.each do |d|
      puts d.to_csv
    end
  end

  def test_summaries
    skip
    datasets = Dataset.all
    datasets = datasets.select{|d| !d.name.nil?}
    datasets.each do |d|
      
      #p d.features.select{|f| f.name.match (/Total/)}
      #p d.features.collect{|f| "#{f.name} #{f.unit} #{f.conditions}"}
      p d.features.uniq.collect{|f| f.name}
    end
    assert_equal 9, datasets.size
=begin
    features = Feature.all.to_a
    #p features.collect do |f|
      #f if f.category == "TOX"
    #end.to_a.flatten.size
    toxcounts = {}
    pccounts = {}
    Nanoparticle.all.each do |np|
      np.measurements.each do |t,v|
        toxcounts[t] ||= 0
        toxcounts[t] += 1#v.uniq.size
      end
      np.physchem_descriptors.each do |t,v|
        pccounts[t] ||= 0
        pccounts[t] += 1#v.uniq.size
      end
    end
    #puts counts.keys.collect{|i| Feature.find(i)}.to_yaml
    #pccounts.each{|e,n| p Feature.find(e),n if n > 100}
    #p toxcounts.collect{|e,n| Feature.find(e).name if n > 1}.uniq
    toxcounts.each{|e,n| p Feature.find(e),n if n > 100}
=end
  end


  def test_import_ld
    skip
    dataset_ids = Import::Enanomapper.import_ld
  end
end
