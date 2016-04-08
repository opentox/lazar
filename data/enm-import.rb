require_relative '../lib/lazar.rb'
include OpenTox
$mongo.database.drop
$gridfs = $mongo.database.fs

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
      nanoparticle.bundles.uniq!
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
      nanoparticle.save!
  end
end
