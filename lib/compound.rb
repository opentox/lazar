# TODO: check
# *** Open Babel Error  in ParseFile
#    Could not find contribution data file.

CACTUS_URI="http://cactus.nci.nih.gov/chemical/structure/"

module OpenTox

  class Compound
    include OpenTox

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
    field :fp4, type: Array
    field :fp4_size, type: Integer

    index({smiles: 1}, {unique: true})

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

    def openbabel_fingerprint type="FP2"
      fp = OpenBabel::OBFingerprint.find_fingerprint(type)
      obmol = OpenBabel::OBMol.new
      obconversion = OpenBabel::OBConversion.new
      obconversion.set_in_format "smi"
      obconversion.read_string obmol, smiles
      result = OpenBabel::VectorUnsignedInt.new
      fp.get_fingerprint(obmol,result)
      # TODO: %ignore *::DescribeBits @ line 163 openbabel/scripts/openbabel-ruby.i
      #p OpenBabel::OBFingerprint.describe_bits(result)
      result = result.to_a
      # convert result to a list of the bits that are set
      # from openbabel/scripts/python/pybel.py line 830
      # see also http://openbabel.org/docs/dev/UseTheLibrary/Python_Pybel.html#fingerprints
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
      bits_set
    end

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles Smiles string
    # @return [OpenTox::Compound] Compound
    def self.from_smiles smiles
      smiles = obconversion(smiles,"smi","can")
      if smiles.empty?
        Compound.find_or_create_by(:warning => "SMILES parsing failed for '#{smiles}', this may be caused by an incorrect SMILES string.")
      else
        Compound.find_or_create_by :smiles => obconversion(smiles,"smi","can")
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
        update(:inchi => result.chomp) unless result.empty?
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

    def neighbors threshold=0.7
      # TODO restrict to dataset
      # from http://blog.matt-swain.com/post/87093745652/chemical-similarity-search-in-mongodb
      qn = fp4.size
      #qmin = qn * threshold
      #qmax = qn / threshold
      #not sure if it is worth the effort of keeping feature counts up to date (compound deletions, additions, ...)
      #reqbits = [count['_id'] for count in db.mfp_counts.find({'_id': {'$in': qfp}}).sort('count', 1).limit(qn - qmin + 1)]
      aggregate = [
        #{'$match': {'mfp.count': {'$gte': qmin, '$lte': qmax}, 'mfp.bits': {'$in': reqbits}}},
        {'$match' =>  {'_id' => {'$ne' => self.id}}}, # remove self
        {'$project' => {
          'tanimoto' => {'$let' => {
            'vars' => {'common' => {'$size' => {'$setIntersection' => ['$fp4', fp4]}}},
            'in' => {'$divide' => ['$$common', {'$subtract' => [{'$add' => [qn, '$fp4_size']}, '$$common']}]}
          }},
          '_id' => 1
        }},
        {'$match' =>  {'tanimoto' => {'$gte' => threshold}}},
        {'$sort' => {'tanimoto' => -1}}
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
p "SDF conversion"
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
      self.class.obconversion(identifier,input_format,output_format,option=nil)
    end
  end
end
