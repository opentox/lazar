module OpenTox

  module Import

    class Enanomapper
      include OpenTox

      def self.mirror dir="."
        #get list of bundle URIs
        bundles = JSON.parse(RestClientWrapper.get('https://data.enanomapper.net/bundle?media=application%2Fjson'))["dataset"]
        File.open(File.join(dir,"bundles.json"),"w+"){|f| f.puts JSON.pretty_generate(bundles)}
        # bundles
          # id/summary
          # id/compound
          # id/substance
          # id/property

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
          if bundle["id"] == 3
          datasets[bundle["URI"]] = Dataset.find_or_create_by(:source => bundle["URI"],:name => bundle["title"])
          end
        end
        # TODO this is only for protein corona
        Dir[File.join(dir,"study-F*.json")].each do |s|
          t = Time.now
          study = JSON.parse(File.read(s))
          np = JSON.parse(File.read(File.join(dir,"nanoparticle-#{study['owner']['substance']['uuid']}.json")))
          core_id = nil
          coating_ids = []
          np["composition"].each do |c|
            uri = c["component"]["compound"]["URI"]
            uri = CGI.escape File.join(uri,"&media=application/json")
            data = JSON.parse(RestClientWrapper.get "https://data.enanomapper.net/query/compound/url/all?media=application/json&search=#{uri}")
            smiles = data["dataEntry"][0]["values"]["https://data.enanomapper.net/feature/http%3A%2F%2Fwww.opentox.org%2Fapi%2F1.1%23SMILESDefault"]
            names = []
            names << data["dataEntry"][0]["values"]["https://data.enanomapper.net/feature/http%3A%2F%2Fwww.opentox.org%2Fapi%2F1.1%23ChemicalNameDefault"]
            names << data["dataEntry"][0]["values"]["https://data.enanomapper.net/feature/http%3A%2F%2Fwww.opentox.org%2Fapi%2F1.1%23IUPACNameDefault"]
            if smiles
              compound = Compound.find_or_create_by(:smiles => smiles)
              compound.names = names.compact
            else
              compound = Compound.find_or_create_by(:names => names)
            end
            compound.save
            if c["relation"] == "HAS_CORE"
              core_id = compound.id.to_s
            elsif c["relation"] == "HAS_COATING"
              coating_ids << compound.id.to_s
            end
          end if np["composition"]
          nanoparticle = Nanoparticle.find_or_create_by(
            :name => np["values"]["https://data.enanomapper.net/identifier/name"],
            :source => np["compound"]["URI"],
            :core_id => core_id,
            :coating_ids => coating_ids
          )
          np["bundles"].keys.each do |bundle_uri|
            nanoparticle.dataset_ids << datasets[bundle_uri].id
          end

          dataset = datasets[np["bundles"].keys.first]
          proteomics_features = {}
          category = study["protocol"]["topcategory"]
          source = study["protocol"]["category"]["term"]

          study["effects"].each do |effect|

            effect["result"]["textValue"] ?  klass = NominalFeature : klass = NumericFeature
            effect["conditions"].delete_if { |k, v| v.nil? }

            if study["protocol"]["category"]["title"].match(/Proteomics/) and effect["result"]["textValue"] and effect["result"]["textValue"].length > 50 # parse proteomics data

              JSON.parse(effect["result"]["textValue"]).each do |identifier, value| # time critical step
                proteomics_features[identifier] ||= NumericFeature.find_or_create_by(:name => identifier, :category => "Proteomics", :unit => "Spectral counts", :source => source,:measured => true)
                nanoparticle.parse_ambit_value proteomics_features[identifier], value, dataset
              end
            else
              name = effect["endpoint"]
              unit = effect["result"]["unit"]
              warnings = []
              case name
              when "Log2 transformed" # use a sensible name
                name = "log2(Net cell association)"
                warnings = ["Original name was 'Log2 transformed'"]
                unit = "log2(mL/ug(Mg))"
              when "Total protein (BCA assay)"
                category = "P-CHEM"
                warnings = ["Category changed from TOX to P-CHEM"]
              end
              feature = klass.find_or_create_by(
                :name => name,
                :unit => unit,
                :category => category,
                :conditions => effect["conditions"],
                :source => study["protocol"]["category"]["term"],
                :measured => true,
                :warnings => warnings
              )
              nanoparticle.parse_ambit_value feature, effect["result"], dataset
            end
          end
    p nanoparticle
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

