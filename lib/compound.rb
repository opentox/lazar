CACTUS_URI="https://cactus.nci.nih.gov/chemical/structure/"

module OpenTox

  # Small molecules with defined chemical structures
  class Compound < Substance
    require_relative "unique_descriptors.rb"
    DEFAULT_FINGERPRINT = "MP2D"

    field :inchi, type: String
    field :smiles, type: String
    field :inchikey, type: String
    field :names, type: Array
    field :cid, type: String
    field :chemblid, type: String
    field :png_id, type: BSON::ObjectId
    field :svg_id, type: BSON::ObjectId
    field :sdf_id, type: BSON::ObjectId
    field :fingerprints, type: Hash, default: {}
    field :default_fingerprint_size, type: Integer

    index({smiles: 1}, {unique: true})

    # Overwrites standard Mongoid method to create fingerprints before database insertion
    def self.find_or_create_by params
      compound = self.find_or_initialize_by params
      compound.default_fingerprint_size = compound.fingerprint(DEFAULT_FINGERPRINT).size
      compound.save
      compound
    end

    # Create chemical fingerprint
    # @param [String] fingerprint type
    # @return [Array<String>] 
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

    # Calculate physchem properties
    # @param [Array<Hash>] list of descriptors
    # @return [Array<Float>]
    def calculate_properties descriptors=PhysChem::OPENBABEL
      calculated_ids = properties.keys
      # BSON::ObjectId instances are not allowed as keys in a BSON document.
      new_ids = descriptors.collect{|d| d.id.to_s} - calculated_ids
      descs = {}
      algos = {}
      new_ids.each do |id|
        descriptor = PhysChem.find id
        descs[[descriptor.library, descriptor.descriptor]]  = descriptor
        algos[descriptor.name] = descriptor
      end
      # avoid recalculating Cdk features with multiple values
      descs.keys.uniq.each do |k|
        descs[k].send(k[0].downcase,k[1],self).each do |n,v|
          properties[algos[n].id.to_s] = v # BSON::ObjectId instances are not allowed as keys in a BSON document.
        end
      end
      save
      descriptors.collect{|d| properties[d.id.to_s]}
    end

    # Match a SMARTS substructure
    # @param [String] smarts
    # @param [TrueClass,FalseClass] count matches or return true/false
    # @return [TrueClass,FalseClass,Fixnum] 
    def smarts_match smarts, count=false
      obconversion = OpenBabel::OBConversion.new
      obmol = OpenBabel::OBMol.new
      obconversion.set_in_format('smi')
      obconversion.read_string(obmol,self.smiles)
      smarts_pattern = OpenBabel::OBSmartsPattern.new
      smarts.collect do |sma|
        smarts_pattern.init(sma.smarts)
        if smarts_pattern.match(obmol)
          count ? value = smarts_pattern.get_map_list.to_a.size : value = 1
        else
          value = 0 
        end
        value
      end
    end

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles 
    # @return [OpenTox::Compound]
    def self.from_smiles smiles
      if smiles.match(/\s/) # spaces seem to confuse obconversion and may lead to invalid smiles
        $logger.warn "SMILES parsing failed for '#{smiles}'', SMILES string contains whitespaces."
        return nil
      end
      smiles = obconversion(smiles,"smi","can") # test if SMILES is correct and return canonical smiles (for compound comparisons)
      if smiles.empty?
        $logger.warn "SMILES parsing failed for '#{smiles}'', this may be caused by an incorrect SMILES string."
        return nil
      else
        Compound.find_or_create_by :smiles => smiles 
      end
    end

    # Create a compound from InChI string
    # @param [String] InChI 
    # @return [OpenTox::Compound] 
    def self.from_inchi inchi
      #smiles = `echo "#{inchi}" | "#{File.join(File.dirname(__FILE__),"..","openbabel","bin","babel")}" -iinchi - -ocan`.chomp.strip
      smiles = obconversion(inchi,"inchi","can")
      if smiles.empty?
        Compound.find_or_create_by(:warnings => ["InChi parsing failed for #{inchi}, this may be caused by an incorrect InChi string or a bug in OpenBabel libraries."])
      else
        Compound.find_or_create_by(:smiles => smiles, :inchi => inchi)
      end
    end

    # Create a compound from SDF 
    # @param [String] SDF 
    # @return [OpenTox::Compound] 
    def self.from_sdf sdf
      # do not store sdf because it might be 2D
      Compound.from_smiles obconversion(sdf,"sdf","can")
    end

    # Create a compound from name. Relies on an external service for name lookups.
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    # @param [String] name, can be also an InChI/InChiKey, CAS number, etc
    # @return [OpenTox::Compound]
    def self.from_name name
      Compound.from_smiles RestClientWrapper.get(File.join(CACTUS_URI,URI.escape(name),"smiles"))
    end

    # Get InChI
    # @return [String] 
    def inchi
      unless self["inchi"]
        result = obconversion(smiles,"smi","inchi")
        update(:inchi => result.chomp) if result and !result.empty?
      end
      self["inchi"]
    end

    # Get InChIKey
    # @return [String]
    def inchikey
      update(:inchikey => obconversion(smiles,"smi","inchikey")) unless self["inchikey"]
      self["inchikey"]
    end

    # Get (canonical) smiles
    # @return [String]
    def smiles
      update(:smiles => obconversion(self["smiles"],"smi","can")) unless self["smiles"] 
      self["smiles"]
    end

    # Get SDF
    # @return [String]
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
    # @return [Array<String>] 
    def names
      update(:names => RestClientWrapper.get("#{CACTUS_URI}#{inchi}/names").split("\n")) unless self["names"] 
      self["names"]
    end

    # Get PubChem Compound Identifier (CID), obtained via REST call to PubChem
    # @return [String] 
    def cid
      pug_uri = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/"
      update(:cid => RestClientWrapper.post(File.join(pug_uri, "compound", "inchi", "cids", "TXT"),{:inchi => inchi}).strip) unless self["cid"] 
      self["cid"]
    end

    # Get ChEMBL database compound id, obtained via REST call to ChEMBL
    # @return [String] 
    def chemblid
      # https://www.ebi.ac.uk/chembldb/ws#individualCompoundByInChiKey
      uri = "https://www.ebi.ac.uk/chemblws/compounds/smiles/#{smiles}.json"
      update(:chemblid => JSON.parse(RestClientWrapper.get(uri))["compounds"].first["chemblId"]) unless self["chemblid"] 
      self["chemblid"]
    end

    def db_neighbors min_sim: 0.1, dataset_id:
      #p fingerprints[DEFAULT_FINGERPRINT]
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
          'similarity' => {'$let' => {
            'vars' => {'common' => {'$size' => {'$setIntersection' => ["$fingerprints.#{DEFAULT_FINGERPRINT}", fingerprints[DEFAULT_FINGERPRINT]]}}},
            'in' => {'$divide' => ['$$common', {'$subtract' => [{'$add' => [default_fingerprint_size, '$default_fingerprint_size']}, '$$common']}]}
          }},
          '_id' => 1,
          #'measurements' => 1,
          'dataset_ids' => 1
        }},
        {'$match' =>  {'similarity' => {'$gte' => min_sim}}},
        {'$sort' => {'similarity' => -1}}
      ]

      # TODO move into aggregate pipeline, see http://stackoverflow.com/questions/30537317/mongodb-aggregation-match-if-value-in-array
      $mongo["substances"].aggregate(aggregate).select{|r| r["dataset_ids"].include? dataset_id}
        
    end
    
    # Convert mmol to mg
    # @return [Float] value in mg
    def mmol_to_mg mmol
      mmol.to_f*molecular_weight
    end

    # Convert mg to mmol
    # @return [Float] value in mmol
    def mg_to_mmol mg
      mg.to_f/molecular_weight
    end
    
    # Calculate molecular weight of Compound with OB and store it in compound object
    # @return [Float] molecular weight
    def molecular_weight
      mw_feature = PhysChem.find_or_create_by(:name => "Openbabel.MW")
      calculate_properties([mw_feature]).first
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
