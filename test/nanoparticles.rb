require_relative "setup.rb"


class NanoparticleTest  < MiniTest::Test

  def setup
    #`mongorestore --db=development #{File.join(File.dirname(__FILE__),"..","dump","production")}`
  end

  def test_mirror
    Import::Enanomapper.mirror File.join(File.dirname(__FILE__),"..","data")
  end

  def test_import
    Import::Enanomapper.import File.join(File.dirname(__FILE__),"..","data")
#    skip
#    dataset_ids = Import::Enanomapper.import
#    assert_operator Nanoparticle.count , :>, 570, "Only #{Nanoparticle.count} nanoparticles imported"
#    assert_operator dataset_ids.size, :>, 8, "Only #{dataset_ids.size} bundles imported"
#    assert dataset_ids.collect{|d| Dataset.find(d).name}.include? ("NanoWiki")
#    assert dataset_ids.collect{|d| Dataset.find(d).name}.include? ("Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
#    p dataset_ids.collect{|d| {d => Dataset.find(d).name}}
#    dataset_ids.collect do |d|
#      d = Dataset.find(d)
      #p d.name
      #puts d.to_csv
#    end
  end

  def test_summaries
    skip
    features = Feature.all.to_a
    #p features.collect do |f|
      #f if f.category == "TOX"
    #end.to_a.flatten.size
    toxcounts = {}
    pccounts = {}
    Nanoparticle.all.each do |np|
      np.toxicities.each do |t,v|
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
  end


  def test_import_ld
    skip
    dataset_ids = Import::Enanomapper.import_ld
  end

  def test_export
    Dataset.all.each do |d|
      puts d.to_csv
    end
  end

  def test_create_model_with_feature_selection
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "7.99 Toxicity (other) ICP-AES", category: "TOX", unit: "mL/ug(Mg)")
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression", :neighbor_algorithm => "nanoparticle_neighbors"})
    nanoparticle = training_dataset.nanoparticles[-34]
    #p nanoparticle.neighbors
    prediction = model.predict nanoparticle
    p prediction
    #p prediction
    refute_nil prediction[:value]
  end

  def test_create_model
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "7.99 Toxicity (other) ICP-AES", category: "TOX", unit: "mL/ug(Mg)")
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression", :neighbor_algorithm => "nanoparticle_neighbors"})
    nanoparticle = training_dataset.nanoparticles[-34]
    #p nanoparticle.neighbors
    prediction = model.predict nanoparticle
    p prediction
    #p prediction
    refute_nil prediction[:value]
  end

  def test_validate_model
    training_dataset = Dataset.find_or_create_by(:name => "Protein Corona Fingerprinting Predicts the Cellular Interaction of Gold and Silver Nanoparticles")
    feature = Feature.find_or_create_by(name: "7.99 Toxicity (other) ICP-AES", category: "TOX", unit: "mL/ug(Mg)")
    #model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_physchem_regression", :neighbor_algorithm => "nanoparticle_neighbors"})
    model = Model::LazarRegression.create(feature, training_dataset, {:prediction_algorithm => "OpenTox::Algorithm::Regression.local_weighted_average", :neighbor_algorithm => "nanoparticle_neighbors"})
    p model
    cv = RegressionCrossValidation.create model
    p cv
  end

end
