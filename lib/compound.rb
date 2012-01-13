@@cactus_uri="http://cactus.nci.nih.gov/chemical/structure/"
@@ambit_uri="http://ambit.uni-plovdiv.bg:8080/ambit2/depict/cdk?search="

module OpenTox

  # Ruby wrapper for OpenTox Compound Webservices (http://opentox.org/dev/apis/api-1.2/structure).
	class Compound 

    # Create a compound from smiles string
    # @example
    #   compound = OpenTox::Compound.from_smiles("c1ccccc1")
    # @param [String] smiles Smiles string
    # @return [OpenTox::Compound] Compound
    def self.from_smiles service_uri, smiles, subjectid=nil
      Compound.new  RestClientWrapper.post(service_uri, smiles, :content_type => 'chemical/x-daylight-smiles').to_s.chomp 
    end

    # Create a compound from inchi string
    # @param [String] smiles InChI string
    # @return [OpenTox::Compound] Compound
    def self.from_inchi(service_uri, inchi)
      Compound.new  RestClientWrapper.post(service_uri, inchi, :content_type => 'chemical/x-inchi').to_s.chomp 
    end

    # Create a compound from sdf string
    # @param [String] smiles SDF string
    # @return [OpenTox::Compound] Compound
    def self.from_sdf(service_uri, sdf)
      Compound.new  RestClientWrapper.post(service_uri, sdf, :content_type => 'chemical/x-mdl-sdfile').to_s.chomp 
    end

    # Create a compound from name. Relies on an external service for name lookups.
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    # @param [String] name name can be also an InChI/InChiKey, CAS number, etc
    # @return [OpenTox::Compound] Compound
    def self.from_name(service_uri, name)
      # paranoid URI encoding to keep SMILES charges and brackets
      inchi = RestClientWrapper.get("#{@@cactus_uri}#{URI.encode(name, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))}/stdinchi").to_s.chomp
      Compound.new File.join(service_uri,URI.escape(inchi))
    end

		# Get InChI
    # @return [String] InChI string
		def to_inchi
      RestClientWrapper.get(@uri, :accept => 'chemical/x-inchi').to_s.chomp if @uri
		end

		# Get (canonical) smiles
    # @return [String] Smiles string
		def to_smiles
      RestClientWrapper.get(@uri, :accept => 'chemical/x-daylight-smiles').chomp
		end

    # Get sdf
    # @return [String] SDF string
		def to_sdf
      RestClientWrapper.get(@uri, :accept => 'chemical/x-mdl-sdfile').chomp
		end

    # Get gif image
    # @return [image/gif] Image data
		def to_gif
			RestClientWrapper.get("#{@@cactus_uri}#{@inchi}/image")
		end

    # Get png image
    # @example
    #   image = compound.to_png
    # @return [image/png] Image data
		def to_png
      RestClientWrapper.get(File.join @uri, "image")
		end

    # Get URI of compound image
    # @return [String] Compound image URI
		def to_image_uri
      File.join @uri, "image"
		end

    # Get all known compound names. Relies on an external service for name lookups.
    # @example
    #   names = compound.to_names
    # @return [String] Compound names
		def to_names
      begin
        RestClientWrapper.get("#{@@cactus_uri}#{@inchi}/names").split("\n")
      rescue
        "not available"
      end
		end

=begin
		# Match a smarts string
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    #   compound.match?("cN") # returns false
    # @param [String] smarts Smarts string
		def match?(smarts)
			obconversion = OpenBabel::OBConversion.new
			obmol = OpenBabel::OBMol.new
			obconversion.set_in_format('inchi')
			obconversion.read_string(obmol,@inchi) 
			smarts_pattern = OpenBabel::OBSmartsPattern.new
			smarts_pattern.init(smarts)
			smarts_pattern.match(obmol)
		end

		# Match an array of smarts strings, returns array with matching smarts
    # @example
    #   compound = OpenTox::Compound.from_name("Benzene")
    #   compound.match(['cc','cN']) # returns ['cc']
    # @param [Array] smarts_array Array with Smarts strings
    # @return [Array] Array with matching Smarts strings
		def match(smarts_array)
      # avoid recreation of OpenBabel objects
			obconversion = OpenBabel::OBConversion.new
			obmol = OpenBabel::OBMol.new
			obconversion.set_in_format('inchi')
			obconversion.read_string(obmol,@inchi) 
			smarts_pattern = OpenBabel::OBSmartsPattern.new
			smarts_array.collect do |smarts|
        smarts_pattern.init(smarts)
        smarts if smarts_pattern.match(obmol)
      end.compact
      #smarts_array.collect { |s| s if match?(s)}.compact
		end

    # Get URI of compound image with highlighted fragments
    #
    # @param [Array] activating Array with activating Smarts strings
    # @param [Array] deactivating Array with deactivating Smarts strings
    # @return [String] URI for compound image with highlighted fragments
    def matching_smarts_image_uri(activating, deactivating)
      activating_smarts = URI.encode "\"#{activating.join("\"/\"")}\""
      deactivating_smarts = URI.encode "\"#{deactivating.join("\"/\"")}\""
      File.join @uri, "smarts/activating", URI.encode(activating_smarts),"deactivating", URI.encode(deactivating_smarts)
    end


    private

    # Convert sdf to inchi
		def self.sdf2inchi(sdf)
			Compound.obconversion(sdf,'sdf','inchi')
		end

    # Convert smiles to inchi
		def self.smiles2inchi(smiles)
			Compound.obconversion(smiles,'smi','inchi')
		end

    # Convert smiles to canonical smiles
		def self.smiles2cansmi(smiles)
			Compound.obconversion(smiles,'smi','can')
		end

    # Convert identifier from OpenBabel input_format to OpenBabel output_format
		def self.obconversion(identifier,input_format,output_format)
			obconversion = OpenBabel::OBConversion.new
			obmol = OpenBabel::OBMol.new
			obconversion.set_in_and_out_formats input_format, output_format
			obconversion.read_string obmol, identifier
			case output_format
			when /smi|can|inchi/
				obconversion.write_string(obmol).gsub(/\s/,'').chomp
			else
				obconversion.write_string(obmol)
			end
		end
=end
	end
end
