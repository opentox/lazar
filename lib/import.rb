module OpenTox

  module Import

    class Enanomapper
      include OpenTox

      def self.import
        #get list of bundle URIs
        bundles = JSON.parse(RestClientWrapper.get('https://data.enanomapper.net/bundle?media=application%2Fjson'))["dataset"]
        datasets = []
        bundles.each do |bundle|
          uri = bundle["URI"]
          dataset = Dataset.find_or_create_by(:source => bundle["URI"],:name => bundle["title"])
          nanoparticles = JSON.parse(RestClientWrapper.get(bundle["dataset"]+"?media=application%2Fjson"))["dataEntry"]
          features = JSON.parse(RestClientWrapper.get(bundle["property"]+"?media=application%2Fjson"))["feature"]
          nanoparticles.each do |np|
            nanoparticle = Nanoparticle.find_or_create_by(
              :name => np["values"]["https://data.enanomapper.net/identifier/name"],
              :source => np["compound"]["URI"],
            )
            dataset.substance_ids << nanoparticle.id
            dataset.substance_ids.uniq!
            studies = JSON.parse(RestClientWrapper.get(File.join(np["compound"]["URI"],"study")))["study"]
            studies.each do |study|
              study["effects"].each do |effect|
                effect["result"]["textValue"] ?  klass = NominalFeature : klass = NumericFeature
                # TODO parse core/coating
                # TODO parse proteomics, they come as a large textValue
                $logger.debug File.join(np["compound"]["URI"],"study")
                effect["conditions"].delete_if { |k, v| v.nil? }
                feature = klass.find_or_create_by(
                  #:source => File.join(np["compound"]["URI"],"study"),
                  :name => "#{study["protocol"]["category"]["title"]} #{study["protocol"]["endpoint"]}",
                  :unit => effect["result"]["unit"],
                  :category => study["protocol"]["topcategory"],
                  :conditions => effect["conditions"]
                )
                nanoparticle.parse_ambit_value feature, effect["result"]
                dataset.feature_ids << feature.id 
                dataset.feature_ids.uniq!
              end
            end
          end
          dataset.save
          datasets << dataset
        end
        datasets.collect{|d| d.id}
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

      def self.dump
        #get list of bundle URIs
        `wget 'https://data.enanomapper.net/bundle?media=application%2Fjson' -O bundles.json`
        json = JSON.parse File.read('./bundles.json')
        json["dataset"].each do |dataset|
          uri = dataset["URI"]
          id = uri.split("/").last
          `wget --header='accept:application/json' '#{uri}' -O 'bundle#{id}'`
          `wget --header='accept:application/json' '#{dataset["summary"]}' -O 'summary#{id}.json'`
          `wget --header='accept:application/json' '#{dataset["compound"]}' -O 'compound#{id}.json'`
          `wget --header='accept:application/json' '#{dataset["substance"]}' -O 'substance#{id}.json'`
          `wget --header='accept:application/json' '#{dataset["property"]}' -O 'property#{id}.json'`
          `wget --header='accept:application/json' '#{dataset["dataset"]}' -O 'dataset#{id}.json'`
          `wget --header='accept:application/json' '#{dataset["matrix"]}' -O 'matrix#{id}.json'`
        end
      end

    end

  end

end

