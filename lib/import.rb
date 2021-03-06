module OpenTox

  # Import data from external databases
  module Import

    class Enanomapper
      include OpenTox

      # Import from eNanoMapper
      def self.import
        # time critical step: JSON parsing (>99%), Oj brings only minor speed gains (~1%)
        datasets = {}
        bundles = JSON.parse(RestClientWrapper.get('https://data.enanomapper.net/bundle', {}, {accept: :json}))["dataset"]
        bundles.each do |bundle|
          datasets[bundle["URI"]] = Dataset.find_or_create_by(:source => bundle["URI"],:name => bundle["title"].strip)
          $logger.debug bundle["title"].strip
          nanoparticles = JSON.parse(RestClientWrapper.get(bundle["dataset"], {}, {accept: :json}))["dataEntry"]
          nanoparticles.each_with_index do |np,n|
            core_id = nil
            coating_ids = []
            np["composition"].each do |c|
              uri = c["component"]["compound"]["URI"]
              data = JSON.parse(RestClientWrapper.get("https://data.enanomapper.net/query/compound/url/all?search=#{uri}", {}, {accept: :json}))
              source = data["dataEntry"][0]["compound"]["URI"]
              smiles = data["dataEntry"][0]["values"]["https://data.enanomapper.net/feature/http%3A%2F%2Fwww.opentox.org%2Fapi%2F1.1%23SMILESDefault"]
              names = []
              names << data["dataEntry"][0]["values"]["https://data.enanomapper.net/feature/http%3A%2F%2Fwww.opentox.org%2Fapi%2F1.1%23ChemicalNameDefault"]
              names << data["dataEntry"][0]["values"]["https://data.enanomapper.net/feature/http%3A%2F%2Fwww.opentox.org%2Fapi%2F1.1%23IUPACNameDefault"]
              if smiles
                compound = Compound.find_or_create_by(:smiles => smiles)
                compound.name = names.first
                compound.names = names.compact
              else
                compound = Compound.find_or_create_by(:name => names.first,:names => names.compact)
              end
              compound.source = source
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

            studies = JSON.parse(RestClientWrapper.get(File.join(np["compound"]["URI"],"study"), {}, {accept: :json}))["study"]
            studies.each do |study|
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
            end
            nanoparticle.save
            print "#{n}, "
          end
          puts
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
