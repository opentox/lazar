# TODO: check
# *** Open Babel Error  in ParseFile
#    Could not find contribution data file.

CACTUS_URI="http://cactus.nci.nih.gov/chemical/structure/"
require 'openbabel'
require "base64"

module OpenTox

  class Compound
    include OpenTox

    field :inchi, type: String
    attr_readonly :inchi
    field :smiles, type: String
    field :inchikey, type: String
    field :names, type: Array
    field :cid, type: String
    field :chemblid, type: String
    field :image_id, type: BSON::ObjectId
    field :sdf_id, type: BSON::ObjectId
    field :fp4, type: Array
    field :fp4_size, type: Integer

    # Overwrites standard Mongoid method to create fingerprints before database insertion
    def self.find_or_create_by params
      compound = self.find_or_initialize_by params
      unless compound.fp4 and !compound.fp4.empty?
        compound.fp4_size = 0
        compound.fp4 = []
        fingerprint = FingerprintSmarts.fingerprint
        Algorithm::Descriptor.smarts_match(compound, fingerprint).each_with_index do |m,i|
          if m > 0
            compound.fp4 << fingerprint[i].id
            compound.fp4_size += 1
          end
        end
      end
      compound.save
      compound
    end

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles Smiles string
    # @return [OpenTox::Compound] Compound
    def self.from_smiles smiles
      # do not store smiles because it might be noncanonical
      Compound.find_or_create_by :inchi => obconversion(smiles,"smi","inchi")
    end

    # Create a compound from inchi string
    # @param inchi [String] smiles InChI string
    # @return [OpenTox::Compound] Compound
    def self.from_inchi inchi
      Compound.find_or_create_by :inchi => inchi
    end

    # Create a compound from sdf string
    # @param sdf [String] smiles SDF string
    # @return [OpenTox::Compound] Compound
    def self.from_sdf sdf
      # do not store sdf because it might be 2D
      Compound.find_or_create_by :inchi => obconversion(sdf,"sdf","inchi")
    end

    # Create a compound from name. Relies on an external service for name lookups.
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    # @param name [String] can be also an InChI/InChiKey, CAS number, etc
    # @return [OpenTox::Compound] Compound
    def self.from_name name
      Compound.find_or_create_by :inchi => RestClientWrapper.get(File.join(CACTUS_URI,URI.escape(name),"stdinchi"))
    end

    # Get InChIKey
    # @return [String] InChI string
    def inchikey
      update(:inchikey => obconversion(inchi,"inchi","inchikey")) unless self["inchikey"]
      self["inchikey"]
    end

    # Get (canonical) smiles
    # @return [String] Smiles string
    def smiles
      update(:smiles => obconversion(inchi,"inchi","smi")) unless self["smiles"] # should give canonical smiles, "can" seems to give incorrect results
      self["smiles"]
    end

    # Get sdf
    # @return [String] SDF string
    def sdf
      if self.sdf_id.nil? 
        sdf = obconversion(inchi,"inchi","sdf")
        file = Mongo::Grid::File.new(sdf, :filename => "#{id}.sdf",:content_type => "chemical/x-mdl-sdfile")
        sdf_id = $gridfs.insert_one file
        update :sdf_id => sdf_id
      end
      $gridfs.find_one(_id: self.sdf_id).data
    end

    # Get png image
    # @example
    #   image = compound.png
    # @return [image/png] Image data
    def png
      if self.image_id.nil?
       png = obconversion(inchi,"inchi","_png2")
       file = Mongo::Grid::File.new(Base64.encode64(png), :filename => "#{id}.png", :content_type => "image/png")
       update(:image_id => $gridfs.insert_one(file))
      end
      Base64.decode64($gridfs.find_one(_id: self.image_id).data)

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

    def neighbors threshold=0.7
      # from http://blog.matt-swain.com/post/87093745652/chemical-similarity-search-in-mongodb
      qn = fp4.size
      #qmin = qn * threshold
      #qmax = qn / threshold
      #not sure if it is worth the effort of keeping feature counts up to date (compound deletions, additions, ...)
      #reqbits = [count['_id'] for count in db.mfp_counts.find({'_id': {'$in': qfp}}).sort('count', 1).limit(qn - qmin + 1)]
      aggregate = [
        #{'$match': {'mfp.count': {'$gte': qmin, '$lte': qmax}, 'mfp.bits': {'$in': reqbits}}},
        {'$match':  {'_id': {'$ne': self.id}}}, # remove self
        {'$project': {
          'tanimoto': {'$let': {
            'vars': {'common': {'$size': {'$setIntersection': ['$fp4', fp4]}}},
            'in': {'$divide': ['$$common', {'$subtract': [{'$add': [qn, '$fp4_size']}, '$$common']}]}
          }},
          '_id': 1
        }},
        {'$match':  {'tanimoto': {'$gte': threshold}}},
        {'$sort': {'tanimoto': -1}}
      ]
      
      $mongo["compounds"].aggregate(aggregate).collect{ |r| [r["_id"], r["tanimoto"]] }
        
    end

    private

    def self.obconversion(identifier,input_format,output_format,option=nil)
      obconversion = OpenBabel::OBConversion.new
      obconversion.set_options(option, OpenBabel::OBConversion::OUTOPTIONS) if option
      obmol = OpenBabel::OBMol.new
      obconversion.set_in_and_out_formats input_format, output_format
      obconversion.read_string obmol, identifier
      case output_format
      when /smi|can|inchi/
        obconversion.write_string(obmol).gsub(/\s/,'').chomp
      when /sdf/
        OpenBabel::OBOp.find_type("Gen3D").do(obmol) 
        sdf = obconversion.write_string(obmol)
        if sdf.match(/.nan/)
          $logger.warn "3D generation failed for compound #{identifier}, trying to calculate 2D structure"
          OpenBabel::OBOp.find_type("Gen2D").do(obmol) 
          sdf = obconversion.write_string(obmol)
          if sdf.match(/.nan/)
            $logger.warn "2D generation failed for compound #{identifier}"
            sdf = nil
          end
        end
        sdf
      else
        obconversion.write_string(obmol)
      end
    end

    def obconversion(identifier,input_format,output_format,option=nil)
      self.class.obconversion(identifier,input_format,output_format,option=nil)
    end
  end
end
