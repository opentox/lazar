module OpenTox

  # Feature for physico-chemical descriptors
  class PhysChem < NumericSubstanceProperty

    field :library, type: String
    field :descriptor, type: String
    field :description, type: String

    JAVA_DIR = File.join(File.dirname(__FILE__),"..","java")
    CDK_JAR = Dir[File.join(JAVA_DIR,"cdk-*jar")].last
    JOELIB_JAR = File.join(JAVA_DIR,"joelib2.jar")
    LOG4J_JAR = File.join(JAVA_DIR,"log4j.jar")
    JMOL_JAR = File.join(JAVA_DIR,"Jmol.jar")

    obexclude = ["cansmi","cansmiNS","formula","InChI","InChIKey","s","smarts","title","L5"]
    OPENBABEL = Hash[OpenBabel::OBDescriptor.list_as_string("descriptors").split("\n").collect do |d|
      name,description = d.split(/\s+/,2)
      ["Openbabel."+name,description] unless obexclude.include? name
    end.compact.sort{|a,b| a[0] <=> b[0]}]

    cdkdescriptors = {}
    CDK_DESCRIPTIONS = YAML.load(`java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptorInfo`)
    CDK_DESCRIPTIONS.each do |d|
      prefix="Cdk."+d[:java_class].split('.').last.sub(/Descriptor/,'')
      d[:names].each { |name| cdkdescriptors[prefix+"."+name] = d[:description] }
    end
    CDK = cdkdescriptors

    # exclude Hashcode (not a physchem property) and GlobalTopologicalChargeIndex (Joelib bug)
    joelibexclude = ["MoleculeHashcode","GlobalTopologicalChargeIndex"]
    # strip Joelib messages from stdout
    JOELIB = Hash[YAML.load(`java -classpath #{JOELIB_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptorInfo | sed '0,/---/d'`).collect do |d|
      name = d[:java_class].sub(/^joelib2.feature.types./,'')
      ["Joelib."+name, "JOELIb does not provide meaningful descriptions, see java/JoelibDescriptors.java for details."] unless joelibexclude.include? name
    end.compact.sort{|a,b| a[0] <=> b[0]}] 

    DESCRIPTORS = OPENBABEL.merge(CDK.merge(JOELIB))

    require_relative "unique_descriptors.rb"

    # Get descriptor features
    # @param [Hash]
    # @return [Array<OpenTox::PhysChem>]
    def self.descriptors desc=DESCRIPTORS
      desc.collect do |name,description|
        lib,desc = name.split('.',2)
        self.find_or_create_by(:name => name, :library => lib, :descriptor => desc, :description => description)
      end
    end

    # Get unique descriptor features
    # @return [Array<OpenTox::PhysChem>]
    def self.unique_descriptors
      udesc = []
      UNIQUEDESCRIPTORS.each do |name|
        lib,desc = name.split('.',2)
        if lib == "Cdk"
          CDK_DESCRIPTIONS.select{|d| desc == d[:java_class].split('.').last.sub('Descriptor','') }.first[:names].each do |n|
            dname = "#{name}.#{n}"
            description = DESCRIPTORS[dname]
            udesc << self.find_or_create_by(:name => dname, :library => lib, :descriptor => desc, :description => description)
          end
        else
          description = DESCRIPTORS[name]
          udesc << self.find_or_create_by(:name => name, :library => lib, :descriptor => desc, :description => description)
        end
      end
      udesc
    end

    # Get OpenBabel descriptor features
    # @return [Array<OpenTox::PhysChem>]
    def self.openbabel_descriptors
      descriptors OPENBABEL
    end

    # Get CDK descriptor features
    # @return [Array<OpenTox::PhysChem>]
    def self.cdk_descriptors
      descriptors CDK
    end

    # Get JOELIB descriptor features
    # @return [Array<OpenTox::PhysChem>]
    def self.joelib_descriptors
      descriptors JOELIB
    end

    # Calculate OpenBabel descriptors
    # @param [String] descriptor type
    # @param [OpenTox::Compound]
    # @return [Hash]
    def openbabel descriptor, compound
      obdescriptor = OpenBabel::OBDescriptor.find_type descriptor
      obmol = OpenBabel::OBMol.new
      obconversion = OpenBabel::OBConversion.new
      obconversion.set_in_format 'smi'
      obconversion.read_string obmol, compound.smiles
      {"#{library.capitalize}.#{descriptor}" => fix_value(obdescriptor.predict(obmol))}
    end

    # Calculate CDK descriptors
    # @param [String] descriptor type
    # @param [OpenTox::Compound]
    # @return [Hash]
    def cdk descriptor, compound
      java_descriptor "cdk", descriptor, compound
    end

    # Calculate JOELIB descriptors
    # @param [String] descriptor type
    # @param [OpenTox::Compound]
    # @return [Hash]
    def joelib descriptor, compound
      java_descriptor "joelib", descriptor, compound
    end

    private

    def java_descriptor lib, descriptor, compound

      sdf_3d = "/tmp/#{SecureRandom.uuid}.sdf"
      File.open(sdf_3d,"w+"){|f| f.print compound.sdf}
      
      # use java system call (rjb blocks within tasks)
      # use Tempfiles to avoid "Argument list too long" error 
      case lib
      when "cdk"
        `java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptors #{sdf_3d} #{descriptor}`
      when "joelib"
        `java -classpath #{JOELIB_JAR}:#{JMOL_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptors  #{sdf_3d} #{descriptor}`
      end
      result = YAML.load_file("#{sdf_3d}#{lib}.yaml").first
      result.keys.each{|k| result[k] = result.delete(k)}
      result
    end

    def fix_value val
      val = val.first if val.is_a? Array and val.size == 1
      val = nil if val == "NaN"
      if val.numeric?
        val = Float(val)
        val = nil if val.nan? or val.infinite?
      end
      val
    end

  end

end
OpenTox::PhysChem.descriptors # load descriptor features
