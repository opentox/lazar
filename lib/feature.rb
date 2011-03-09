module OpenTox
  class Feature
    include OpenTox

    def self.find(uri, subjectid=nil)
      return nil unless uri   
      feature = Feature.new uri
      if (CONFIG[:yaml_hosts].include?(URI.parse(uri).host))
        feature.add_metadata YAML.load(RestClientWrapper.get(uri,{:accept => "application/x-yaml", :subjectid => subjectid}))
      else
        feature.add_metadata  Parser::Owl::Dataset.new(uri).load_metadata
      end
      feature
    end
    
    # provides domain (possible target values) of classification feature 
    # @return [Array] list with possible target values
    def domain
      if metadata[OT.acceptValue]
        raise "accept value found, remove hack and implement correctly"
      else
      if @uri=~/feature\/26221/ || @uri=~/feature\/221726/ 
        return ["mutagen" , "nonmutagen"]
      end
        return [true, false]
      end
    end
    
    # provides feature type, possible types are "regression" or "classification"
    # @return [String] feature type, unknown if OT.isA property is unknown/ not set
    def feature_type
      case metadata[OT.isA]
      when /NominalFeature/
        "classification"
      when /NumericFeature/
        "regression"
      else
        "unknown"
      end
    end    
    
  end
end
