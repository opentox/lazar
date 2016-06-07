require_relative "setup.rb"


class NanoparticleTest  < MiniTest::Test
  include OpenTox::Validation

  def setup
    # TODO: multiple runs create duplicates
    #$mongo.database.drop
    #Import::Enanomapper.import File.join(File.dirname(__FILE__),"data","enm")
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

  def test_inspect_cv
    cv = CrossValidation.all.sort_by{|cv| cv.created_at}.last
    #p cv
    #p cv.id
    #cv.correlation_plot_id = nil
    File.open("tmp.pdf","w+"){|f| f.puts cv.correlation_plot}
    #p cv.statistics
    #p cv.model.training_dataset.substances.first.physchem_descriptors.keys.collect{|d| Feature.find(d).name}
    CrossValidation.all.sort_by{|cv| cv.created_at}.reverse.each do |cv|
      p cv.name
      p cv.created_at
      begin
      p cv.r_squared
      rescue
      end
    end
  end
  def test_inspect_worst_prediction
  
    cv = CrossValidation.all.sort_by{|cv| cv.created_at}.last
    worst_predictions = cv.worst_predictions(n: 3,show_neigbors: false)
    assert_equal 3, worst_predictions.size
    assert_kind_of Integer, worst_predictions.first[:neighbors]
    worst_predictions = cv.worst_predictions
    assert_equal 5, worst_predictions.size
    assert_kind_of Array, worst_predictions.first[:neighbors]
    assert_kind_of Integer, worst_predictions.first[:neighbors].first[:common_descriptors]
    puts worst_predictions.to_yaml
    worst_predictions = cv.worst_predictions(n: 2, show_common_descriptors: true)
    #puts worst_predictions.to_yaml
    assert_equal 2, worst_predictions.size
    assert_kind_of Array, worst_predictions.first[:neighbors]
    refute_nil worst_predictions.first[:neighbors].first[:common_descriptors]
    #p cv.model.training_dataset.features
  end

  def test_validate_model
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    #feature = Feature.find_or_create_by(name: "Net cell association", category: "TOX", unit: "mL/ug(Mg)")
    feature = Feature.find_or_create_by(name: "Log2 transformed", category: "TOX")
    
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_weighted_average", :feature_selection_algorithm => :correlation_filter, :neighbor_algorithm => "physchem_neighbors", :neighbor_algorithm_parameters => {:min_sim => 0.5}})
    cv = RegressionCrossValidation.create model
    p cv.rmse
    p cv.r_squared
    #File.open("tmp.pdf","w+"){|f| f.puts cv.correlation_plot}
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_pls_model
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "Log2 transformed", category: "TOX")
    
    model = Model::LazarRegression.create(feature, training_dataset, {
      :prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression",
      :feature_selection_algorithm => :correlation_filter,
      :prediction_algorithm_parameters => {:method => 'pls'},
      #:feature_selection_algorithm_parameters => {:category => "P-CHEM"},
      #:feature_selection_algorithm_parameters => {:category => "Proteomics"},
      :neighbor_algorithm => "physchem_neighbors",
      :neighbor_algorithm_parameters => {:min_sim => 0.5}
    })
    cv = RegressionCrossValidation.create model
    p cv.rmse
    p cv.r_squared
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_random_forest_model
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "Log2 transformed", category: "TOX")
    
    model = Model::LazarRegression.create(feature, training_dataset, {
      :prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression",
      :prediction_algorithm_parameters => {:method => 'rf'},
      :feature_selection_algorithm => :correlation_filter,
      #:feature_selection_algorithm_parameters => {:category => "P-CHEM"},
      #:feature_selection_algorithm_parameters => {:category => "Proteomics"},
      :neighbor_algorithm => "physchem_neighbors",
      :neighbor_algorithm_parameters => {:min_sim => 0.5}
    })
    cv = RegressionCrossValidation.create model
    p cv.rmse
    p cv.r_squared
    refute_nil cv.r_squared
    refute_nil cv.rmse
  end

  def test_validate_proteomics_pls_model
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "Log2 transformed", category: "TOX")
    
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression", :neighbor_algorithm => "proteomics_neighbors", :neighbor_algorithm_parameters => {:min_sim => 0.5}})
    cv = RegressionCrossValidation.create model
    p cv.rmse
    p cv.r_squared
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
