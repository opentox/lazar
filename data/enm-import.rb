require_relative '../lib/lazar.rb'
include OpenTox


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
      np["composition"].each do |comp|
        case comp["relation"]
        when "HAS_CORE"
          nanoparticle[:core] = comp["component"]["compound"]["URI"]
        when "HAS_COATING"
          nanoparticle[:coating] ||= []
          nanoparticle[:coating] << comp["component"]["compound"]["URI"]
        end
      end if np["composition"]
      np["values"].each do |u,v|
        if u.match(/property/)
          name, unit = nil
          features.each do |uri,feat|
            if u.match(/#{uri}/)
              name = feat["title"]
              unit = feat["units"]
            end
          end
          feature = Feature.find_or_create_by(
            :name => name,
            :unit => unit,
            #:source => uri
          )
          nanoparticle[:features] ||= {}
          if v.size == 1 and v.first.keys == ["loValue"]
            nanoparticle[:features][feature.id] = v.first["loValue"]
          else
            #TODO
          end
        end
      end
      p nanoparticle
      nanoparticle.save
  end
end
