module OpenTox

  module Import

    class Enanomapper
      include OpenTox

      def self.import
        #get list of bundle URIs
        bundles = JSON.parse(RestClientWrapper.get('https://data.enanomapper.net/bundle?media=application%2Fjson'))["dataset"]
        bundles.each do |bundle|
          uri = bundle["URI"]
          nanoparticles = JSON.parse(RestClientWrapper.get(bundle["dataset"]+"?media=application%2Fjson"))["dataEntry"]
          features = JSON.parse(RestClientWrapper.get(bundle["property"]+"?media=application%2Fjson"))["feature"]
          nanoparticles.each do |np|
              nanoparticle = Nanoparticle.find_or_create_by(
                :name => np["values"]["https://data.enanomapper.net/identifier/name"],
                :source => np["compound"]["URI"],
              )
              nanoparticle.bundles << uri
              np["composition"].each do |comp|
                case comp["relation"]
                when "HAS_CORE"
                  nanoparticle.core = comp["component"]["compound"]["URI"]
                when "HAS_COATING"
                  nanoparticle.coating << comp["component"]["compound"]["URI"]
                end
              end if np["composition"]
              np["values"].each do |u,v|
                if u.match(/property/)
                  name, unit, source = nil
                  features.each do |uri,feat|
                    if u.match(/#{uri}/)
                      name = feat["title"]
                      unit = feat["units"]
                      source = uri
                    end
                  end
                  feature = Feature.find_or_create_by(
                    :name => name,
                    :unit => unit,
                    :source => source
                  )
                end
                v.each{|value| nanoparticle.parse_ambit_value feature, value} if v.is_a? Array
              end
              nanoparticle.bundles.uniq!
              nanoparticle.physchem_descriptors.each{|f,v| v.uniq!}
              nanoparticle.toxicities.each{|f,v| v.uniq!}
              nanoparticle.save!
          end
        end

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

end

