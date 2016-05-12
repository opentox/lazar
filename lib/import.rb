module OpenTox

  module Import

    class Enanomapper
      include OpenTox

      def self.mirror dir="."
        #get list of bundle URIs
        bundles = JSON.parse(RestClientWrapper.get('https://data.enanomapper.net/bundle?media=application%2Fjson'))["dataset"]
        File.open(File.join(dir,"bundles.json"),"w+"){|f| f.puts JSON.pretty_generate(bundles)}
        bundles.each do |bundle|
          p bundle["title"]
          nanoparticles = JSON.parse(RestClientWrapper.get(bundle["dataset"]+"?media=application%2Fjson"))["dataEntry"]
          p nanoparticles.size
          nanoparticles.each do |nanoparticle|
            uuid = nanoparticle["values"]["https://data.enanomapper.net/identifier/uuid"]
            $logger.debug uuid
            File.open(File.join(dir,"nanoparticle-#{uuid}.json"),"w+"){|f| f.puts JSON.pretty_generate(nanoparticle)}
            studies = JSON.parse(RestClientWrapper.get(File.join(nanoparticle["compound"]["URI"],"study")))["study"]
            p uuid if studies.size < 1 
            studies.each do |study|
              File.open(File.join(dir,"study-#{study["uuid"]}.json"),"w+"){|f| f.puts JSON.pretty_generate(study)}
            end
          end
        end
      end

      def self.import dir="."
        datasets = {}
        JSON.parse(File.read(File.join(dir,"bundles.json"))).each do |bundle|
          datasets[bundle["URI"]] = Dataset.find_or_create_by(:source => bundle["URI"],:name => bundle["title"])
        end
        Dir[File.join(dir,"study*.json")].each do |s|
          study = JSON.parse(File.read(s))
          np = JSON.parse(File.read(File.join(dir,"nanoparticle-#{study['owner']['substance']['uuid']}.json")))
          nanoparticle = Nanoparticle.find_or_create_by(
            :name => np["values"]["https://data.enanomapper.net/identifier/name"],
            :source => np["compound"]["URI"],
          )
          np["bundles"].keys.each do |bundle_uri|
            #datasets[bundle_uri].substance_ids << nanoparticle.id
            nanoparticle["dataset_ids"] << datasets[bundle_uri].id
          end
          bundle = datasets[np["bundles"].keys.first].id if np["bundles"].size == 1
          study["effects"].each do |effect|
            effect["result"]["textValue"] ?  klass = NominalFeature : klass = NumericFeature
            # TODO parse core/coating
            #$logger.debug File.join(np["compound"]["URI"],"study")
            effect["conditions"].delete_if { |k, v| v.nil? }
            # parse proteomics data
            if study["protocol"]["category"]["title"].match(/Proteomics/) and effect["result"]["textValue"] and effect["result"]["textValue"].length > 50
              JSON.parse(effect["result"]["textValue"]).each do |identifier, value|
                feature = klass.find_or_create_by(
                  :name => identifier,
                  :category => "Proteomics",
                )
                nanoparticle.parse_ambit_value feature, value, bundle
              end
            else
              feature = klass.find_or_create_by(
                :name => "#{study["protocol"]["category"]["title"]} #{study["protocol"]["endpoint"]}",
                :unit => effect["result"]["unit"],
                :category => study["protocol"]["topcategory"],
                :conditions => effect["conditions"]
              )
              nanoparticle.parse_ambit_value feature, effect["result"], bundle
            end
          end
          nanoparticle.save
        end
        datasets.each do |u,d|
          d.feature_ids.uniq!
          d.substance_ids.uniq!
          d.save
        end
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

