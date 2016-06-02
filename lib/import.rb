module OpenTox

  module Import

    class Enanomapper
      include OpenTox

      def self.mirror dir="."
        #get list of bundle URIs
        bundles = JSON.parse(RestClientWrapper.get('https://data.enanomapper.net/bundle?media=application%2Fjson'))["dataset"]
        File.open(File.join(dir,"bundles.json"),"w+"){|f| f.puts JSON.pretty_generate(bundles)}
        bundles.each do |bundle|
          $logger.debug bundle["title"]
          nanoparticles = JSON.parse(RestClientWrapper.get(bundle["dataset"]+"?media=application%2Fjson"))["dataEntry"]
          $logger.debug nanoparticles.size
          nanoparticles.each do |nanoparticle|
            uuid = nanoparticle["values"]["https://data.enanomapper.net/identifier/uuid"]
            $logger.debug uuid
            File.open(File.join(dir,"nanoparticle-#{uuid}.json"),"w+"){|f| f.puts JSON.pretty_generate(nanoparticle)}
            studies = JSON.parse(RestClientWrapper.get(File.join(nanoparticle["compound"]["URI"],"study")))["study"]
            $logger.debug uuid if studies.size < 1 
            studies.each do |study|
              File.open(File.join(dir,"study-#{study["uuid"]}.json"),"w+"){|f| f.puts JSON.pretty_generate(study)}
            end
          end
        end
      end

      def self.import dir="."
        start_time = Time.now
        t1 = 0
        t2 = 0
        datasets = {}
        JSON.parse(File.read(File.join(dir,"bundles.json"))).each do |bundle|
          datasets[bundle["URI"]] = Dataset.find_or_create_by(:source => bundle["URI"],:name => bundle["title"])
        end
        Dir[File.join(dir,"study*.json")].each do |s|
          t = Time.now
          study = JSON.parse(File.read(s))
          np = JSON.parse(File.read(File.join(dir,"nanoparticle-#{study['owner']['substance']['uuid']}.json")))
          core = {}
          coating = []
          np["composition"].each do |c|
            if c["relation"] == "HAS_CORE"
              core = {
                :uri => c["component"]["compound"]["URI"],
                :name => c["component"]["values"]["https://data.enanomapper.net/feature/http%3A%2F%2Fwww.opentox.org%2Fapi%2F1.1%23ChemicalNameDefault"]
              }
            elsif c["relation"] == "HAS_COATING"
              coating << {
                :uri => c["component"]["compound"]["URI"],
                :name => c["component"]["values"]["https://data.enanomapper.net/feature/http%3A%2F%2Fwww.opentox.org%2Fapi%2F1.1%23ChemicalNameDefault"]
              }
            end
          end if np["composition"]
          nanoparticle = Nanoparticle.find_or_create_by(
            :name => np["values"]["https://data.enanomapper.net/identifier/name"],
            :source => np["compound"]["URI"],
            :core => core,
            :coating => coating
          )
          np["bundles"].keys.each do |bundle_uri|
            nanoparticle.dataset_ids << datasets[bundle_uri].id
          end
          dataset = datasets[np["bundles"].keys.first]
          proteomics_features = {}
          study["effects"].each do |effect|
            effect["result"]["textValue"] ?  klass = NominalFeature : klass = NumericFeature
            effect["conditions"].delete_if { |k, v| v.nil? }
            if study["protocol"]["category"]["title"].match(/Proteomics/) and effect["result"]["textValue"] and effect["result"]["textValue"].length > 50 # parse proteomics data
              JSON.parse(effect["result"]["textValue"]).each do |identifier, value| # time critical step
                proteomics_features[identifier] ||= NumericFeature.find_or_create_by(:name => identifier, :category => "Proteomics")
                nanoparticle.parse_ambit_value proteomics_features[identifier], value, dataset
              end
            else
              feature = klass.find_or_create_by(
                :name => effect["endpoint"],
                :unit => effect["result"]["unit"],
                :category => study["protocol"]["topcategory"],
                :conditions => effect["conditions"]
              )
              nanoparticle.parse_ambit_value feature, effect["result"], dataset
            end
          end
          nanoparticle.save
        end
        datasets.each { |u,d| d.save }
      end

=begin
      def self.import_ld # defunct, AMBIT JSON_LD does not have substance entries
        #get list of bundle URIs
        bundles = JSON.parse(RestClientWrapper.get('https://data.enanomapper.net/bundle?media=application%2Fjson'))["dataset"]
        datasets = []
        bundles.each do |bundle|
          uri = bundle["URI"]
          study = JSON.parse(`curl -H 'Accept:application/ld+json' '#{uri}/substance'`)
          study["@graph"].each do |i|
            puts i.to_yaml if i.keys.include? "sio:has-value"
          end
        end
        datasets.collect{|d| d.id}
      end
=end

    end

  end

end

