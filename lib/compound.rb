# TODO: check
# *** Open Babel Error  in ParseFile
#    Could not find contribution data file.

CACTUS_URI="http://cactus.nci.nih.gov/chemical/structure/"

module OpenTox

  class Compound
    include OpenTox

    DEFAULT_FINGERPRINT = "MP2D"

    field :inchi, type: String
    field :smiles, type: String
    field :inchikey, type: String
    field :names, type: Array
    field :warning, type: String
    field :cid, type: String
    field :chemblid, type: String
    field :png_id, type: BSON::ObjectId
    field :svg_id, type: BSON::ObjectId
    field :sdf_id, type: BSON::ObjectId
    field :molecular_weight, type: Float
    field :fingerprints, type: Hash, default: {}
    field :physchem, type: Hash, default: {}
    field :default_fingerprint_size, type: Integer
    field :dataset_ids, type: Array, default: []
    field :features, type: Hash, default: {}

    index({smiles: 1}, {unique: true})
    #index({default_fingerprint: 1}, {unique: false})

    # Overwrites standard Mongoid method to create fingerprints before database insertion
    def self.find_or_create_by params
      compound = self.find_or_initialize_by params
      compound.default_fingerprint_size = compound.fingerprint(DEFAULT_FINGERPRINT).size
      compound.save
      compound
    end

    def fingerprint type=DEFAULT_FINGERPRINT
      unless fingerprints[type]
        return [] unless self.smiles
        #http://openbabel.org/docs/dev/FileFormats/MolPrint2D_format.html#molprint2d-format
        if type == "MP2D"
          fp = obconversion(smiles,"smi","mpd").strip.split("\t")
          name = fp.shift # remove Title
          fingerprints[type] = fp.uniq # no fingerprint counts
        #http://openbabel.org/docs/dev/FileFormats/Multilevel_Neighborhoods_of_Atoms_(MNA).html
        elsif type== "MNA"
          level = 2 # TODO: level as parameter, evaluate level 1, see paper
          fp = obconversion(smiles,"smi","mna","xL\"#{level}\"").split("\n")
          fp.shift # remove Title
          fingerprints[type] = fp
        else # standard fingerprints
          fp = OpenBabel::OBFingerprint.find_fingerprint(type)
          obmol = OpenBabel::OBMol.new
          obconversion = OpenBabel::OBConversion.new
          obconversion.set_in_format "smi"
          obconversion.read_string obmol, self.smiles
          result = OpenBabel::VectorUnsignedInt.new
          fp.get_fingerprint(obmol,result)
          # TODO: %ignore *::DescribeBits @ line 163 openbabel/scripts/openbabel-ruby.i
          #p OpenBabel::OBFingerprint.describe_bits(result)
          # convert result to a list of the bits that are set
          # from openbabel/scripts/python/pybel.py line 830
          # see also http://openbabel.org/docs/dev/UseTheLibrary/Python_Pybel.html#fingerprints
          result = result.to_a
          bitsperint = OpenBabel::OBFingerprint.getbitsperint()
          bits_set = []
          start = 1
          result.each do |x|
            i = start
            while x > 0 do
              bits_set << i if (x % 2) == 1
              x >>= 1
              i += 1
            end
            start += bitsperint
          end
          fingerprints[type] = bits_set
        end
        save
      end
      fingerprints[type]
    end

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles Smiles string
    # @return [OpenTox::Compound] Compound
    def self.from_smiles smiles
      return nil if smiles.match(/\s/) # spaces seem to confuse obconversion and may lead to invalid smiles
      smiles = obconversion(smiles,"smi","can") # test if SMILES is correct and return canonical smiles (for compound comparisons)
      if smiles.empty?
        return nil
        #Compound.find_or_create_by(:warning => "SMILES parsing failed for '#{smiles}', this may be caused by an incorrect SMILES string.")
      else
        #Compound.find_or_create_by :smiles => obconversion(smiles,"smi","can") # test if SMILES is correct and return canonical smiles (for compound comparisons)
        Compound.find_or_create_by :smiles => smiles 
      end
    end

    # Create a compound from inchi string
    # @param inchi [String] smiles InChI string
    # @return [OpenTox::Compound] Compound
    def self.from_inchi inchi
      # Temporary workaround for OpenBabels Inchi bug
      # http://sourceforge.net/p/openbabel/bugs/957/
      # bug has not been fixed in latest git/development version
      #smiles = `echo "#{inchi}" | "#{File.join(File.dirname(__FILE__),"..","openbabel","bin","babel")}" -iinchi - -ocan`.chomp.strip
      smiles = obconversion(inchi,"inchi","can")
      if smiles.empty?
        Compound.find_or_create_by(:warning => "InChi parsing failed for #{inchi}, this may be caused by an incorrect InChi string or a bug in OpenBabel libraries.")
      else
        Compound.find_or_create_by(:smiles => smiles, :inchi => inchi)
      end
    end

    # Create a compound from sdf string
    # @param sdf [String] smiles SDF string
    # @return [OpenTox::Compound] Compound
    def self.from_sdf sdf
      # do not store sdf because it might be 2D
      Compound.from_smiles obconversion(sdf,"sdf","can")
    end

    # Create a compound from name. Relies on an external service for name lookups.
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    # @param name [String] can be also an InChI/InChiKey, CAS number, etc
    # @return [OpenTox::Compound] Compound
    def self.from_name name
      Compound.from_smiles RestClientWrapper.get(File.join(CACTUS_URI,URI.escape(name),"smiles"))
    end

    # Get InChI
    # @return [String] InChI string
    def inchi
      unless self["inchi"]

        result = obconversion(smiles,"smi","inchi")
        #result = `echo "#{self.smiles}" | "#{File.join(File.dirname(__FILE__),"..","openbabel","bin","babel")}" -ismi - -oinchi`.chomp
        update(:inchi => result.chomp) if result and !result.empty?
      end
      self["inchi"]
    end

    # Get InChIKey
    # @return [String] InChIKey string
    def inchikey
      update(:inchikey => obconversion(smiles,"smi","inchikey")) unless self["inchikey"]
      self["inchikey"]
    end

    # Get (canonical) smiles
    # @return [String] Smiles string
    def smiles
      update(:smiles => obconversion(self["smiles"],"smi","can")) unless self["smiles"] 
      self["smiles"]
    end

    # Get sdf
    # @return [String] SDF string
    def sdf
      if self.sdf_id.nil? 
        sdf = obconversion(smiles,"smi","sdf")
        file = Mongo::Grid::File.new(sdf, :filename => "#{id}.sdf",:content_type => "chemical/x-mdl-sdfile")
        sdf_id = $gridfs.insert_one file
        update :sdf_id => sdf_id
      end
      $gridfs.find_one(_id: self.sdf_id).data
    end

    # Get SVG image
    # @return [image/svg] Image data
    def svg
      if self.svg_id.nil?
       svg = obconversion(smiles,"smi","svg")
       file = Mongo::Grid::File.new(svg, :filename => "#{id}.svg", :content_type => "image/svg")
       update(:svg_id => $gridfs.insert_one(file))
      end
      $gridfs.find_one(_id: self.svg_id).data

    end

    # Get png image
    # @example
    #   image = compound.png
    # @return [image/png] Image data
    def png
      if self.png_id.nil?
       png = obconversion(smiles,"smi","_png2")
       file = Mongo::Grid::File.new(Base64.encode64(png), :filename => "#{id}.png", :content_type => "image/png")
       update(:png_id => $gridfs.insert_one(file))
      end
      Base64.decode64($gridfs.find_one(_id: self.png_id).data)

    end

    # Get all known compound names. Relies on an external service for name lookups.
    # @example
    #   names = compound.names
    # @return [String] Compound names
    def names
      update(:names => RestClientWrapper.get("#{CACTUS_URI}#{inchi}/names").split("\n")) unless self["names"] 
      self["names"]
    end

    # @return [String] PubChem Compound Identifier (CID), derieved via restcall to pubchem
    def cid
      pug_uri = "http://pubchem.ncbi.nlm.nih.gov/rest/pug/"
      update(:cid => RestClientWrapper.post(File.join(pug_uri, "compound", "inchi", "cids", "TXT"),{:inchi => inchi}).strip) unless self["cid"] 
      self["cid"]
    end

    # @return [String] ChEMBL database compound id, derieved via restcall to chembl
    def chemblid
      # https://www.ebi.ac.uk/chembldb/ws#individualCompoundByInChiKey
      uri = "http://www.ebi.ac.uk/chemblws/compounds/smiles/#{smiles}.json"
      update(:chemblid => JSON.parse(RestClientWrapper.get(uri))["compounds"].first["chemblId"]) unless self["chemblid"] 
      self["chemblid"]
    end

    def fingerprint_count_neighbors params
      # TODO fix
      neighbors = []
      query_fingerprint = self.fingerprint params[:type]
      training_dataset = Dataset.find(params[:training_dataset_id]).compounds.each do |compound|
        unless self == compound
          candidate_fingerprint = compound.fingerprint params[:type]
          features = (query_fingerprint + candidate_fingerprint).uniq
          min_sum = 0
          max_sum = 0
          features.each do |f|
            min,max = [query_fingerprint.count(f),candidate_fingerprint.count(f)].minmax
            min_sum += min
            max_sum += max
          end
          max_sum == 0 ? sim = 0 : sim = min_sum/max_sum.to_f
          neighbors << [compound.id, sim] if sim and sim >= params[:min_sim]
        end
      end
      neighbors.sort{|a,b| b.last <=> a.last}
    end

    def fingerprint_neighbors params
      bad_request_error "Incorrect parameters '#{params}' for Compound#fingerprint_neighbors. Please provide :type, :training_dataset_id, :min_sim." unless params[:type] and params[:training_dataset_id] and params[:min_sim]
      neighbors = []
      if params[:type] == DEFAULT_FINGERPRINT
        neighbors = db_neighbors params
      else 
        query_fingerprint = self.fingerprint params[:type]
        training_dataset = Dataset.find(params[:training_dataset_id])
        prediction_feature = training_dataset.features.first
        training_dataset.compounds.each do |compound|
          #unless self == compound
            candidate_fingerprint = compound.fingerprint params[:type]
            sim = (query_fingerprint & candidate_fingerprint).size/(query_fingerprint | candidate_fingerprint).size.to_f
            feature_values = training_dataset.values(compound,prediction_feature)
            neighbors << {"_id" => compound.id, "features" => {prediction_feature.id.to_s => feature_values}, "tanimoto" => sim} if sim >= params[:min_sim]
          #end
        end
        neighbors.sort!{|a,b| b["tanimoto"] <=> a["tanimoto"]}
      end
      neighbors
    end

    def fminer_neighbors params
      bad_request_error "Incorrect parameters for Compound#fminer_neighbors. Please provide :feature_dataset_id, :min_sim." unless params[:feature_dataset_id] and params[:min_sim]
      feature_dataset = Dataset.find params[:feature_dataset_id]
      query_fingerprint = Algorithm::Descriptor.smarts_match(self, feature_dataset.features)
      neighbors = []

      # find neighbors
      feature_dataset.data_entries.each_with_index do |candidate_fingerprint, i|
        sim = Algorithm::Similarity.tanimoto candidate_fingerprint, query_fingerprint
        if sim >= params[:min_sim]
          neighbors << [feature_dataset.compound_ids[i],sim] # use compound_ids, instantiation of Compounds is too time consuming
        end
      end
      neighbors
    end

    def physchem_neighbors params
      feature_dataset = Dataset.find params[:feature_dataset_id]
      query_fingerprint = Algorithm.run params[:feature_calculation_algorithm], self, params[:descriptors]
      neighbors = []
      feature_dataset.data_entries.each_with_index do |candidate_fingerprint, i|
        # TODO implement pearson and cosine similarity separatly
        R.assign "x", query_fingerprint
        R.assign "y", candidate_fingerprint
        # pearson r
        #sim = R.eval("cor(x,y,use='complete.obs',method='pearson')").to_ruby
        #p "pearson"
        #p sim
        #p "cosine"
        sim = R.eval("x %*% y / sqrt(x%*%x * y%*%y)").to_ruby.first
        #p sim
        if sim >= params[:min_sim]
          neighbors << [feature_dataset.compound_ids[i],sim] # use compound_ids, instantiation of Compounds is too time consuming
        end
      end
      neighbors
    end

    def db_neighbors params
      # from http://blog.matt-swain.com/post/87093745652/chemical-similarity-search-in-mongodb

      #qn = default_fingerprint_size
      #qmin = qn * threshold
      #qmax = qn / threshold
      #not sure if it is worth the effort of keeping feature counts up to date (compound deletions, additions, ...)
      #reqbits = [count['_id'] for count in db.mfp_counts.find({'_id': {'$in': qfp}}).sort('count', 1).limit(qn - qmin + 1)]
      aggregate = [
        #{'$match': {'mfp.count': {'$gte': qmin, '$lte': qmax}, 'mfp.bits': {'$in': reqbits}}},
        #{'$match' =>  {'_id' => {'$ne' => self.id}}}, # remove self
        {'$project' => {
          'tanimoto' => {'$let' => {
            'vars' => {'common' => {'$size' => {'$setIntersection' => ["$fingerprints.#{DEFAULT_FINGERPRINT}", fingerprints[DEFAULT_FINGERPRINT]]}}},
            #'vars' => {'common' => {'$size' => {'$setIntersection' => ["$default_fingerprint", default_fingerprint]}}},
            'in' => {'$divide' => ['$$common', {'$subtract' => [{'$add' => [default_fingerprint_size, '$default_fingerprint_size']}, '$$common']}]}
          }},
          '_id' => 1,
          'features' => 1,
          'dataset_ids' => 1
        }},
        {'$match' =>  {'tanimoto' => {'$gte' => params[:min_sim]}}},
        {'$sort' => {'tanimoto' => -1}}
      ]
      
      $mongo["compounds"].aggregate(aggregate).select{|r| r["dataset_ids"].include? params[:training_dataset_id]}


      #$mongo["compounds"].aggregate(aggregate).collect{ |r| [r["_id"], r["tanimoto"]] }
        
    end
    
    # Convert mg to mmol
    # @return [Float] value in mg
    def mmol_to_mg mmol
      mmol.to_f*molecular_weight
    end

    # Convert mmol to mg
    # @return [Float] value in mg
    def mg_to_mmol mg
      mg.to_f/molecular_weight
    end
    
    # Calculate molecular weight of Compound with OB and store it in object
    # @return [Float] molecular weight
    def molecular_weight
      if self["molecular_weight"]==0.0 || self["molecular_weight"].nil?
        update(:molecular_weight => OpenTox::Algorithm::Descriptor.physchem(self, ["Openbabel.MW"]).first)
      end
      self["molecular_weight"].to_f
    end

    private

    def self.obconversion(identifier,input_format,output_format,option=nil)
      obconversion = OpenBabel::OBConversion.new
      obconversion.set_options(option, OpenBabel::OBConversion::OUTOPTIONS) if option
      obmol = OpenBabel::OBMol.new
      obconversion.set_in_and_out_formats input_format, output_format
      return nil if identifier.nil?
      obconversion.read_string obmol, identifier
      case output_format
      when /smi|can|inchi/
        obconversion.write_string(obmol).gsub(/\s/,'').chomp
      when /sdf/
        # TODO: find disconnected structures
        # strip_salts
        # separate
        obmol.add_hydrogens
        builder = OpenBabel::OBBuilder.new
        builder.build(obmol)

        sdf = obconversion.write_string(obmol)
print sdf
        if sdf.match(/.nan/)
          
          $logger.warn "3D generation failed for compound #{identifier}, trying to calculate 2D structure"
          obconversion.set_options("gen2D", OpenBabel::OBConversion::GENOPTIONS)
          sdf = obconversion.write_string(obmol)
          if sdf.match(/.nan/)
            $logger.warn "2D generation failed for compound #{identifier}, rendering without coordinates."
            obconversion.remove_option("gen2D", OpenBabel::OBConversion::GENOPTIONS)
            sdf = obconversion.write_string(obmol)
          end
        end
        sdf
      else
        obconversion.write_string(obmol)
      end
    end

    def obconversion(identifier,input_format,output_format,option=nil)
      self.class.obconversion(identifier,input_format,output_format,option)
    end
  end
end
