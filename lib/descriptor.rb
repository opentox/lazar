require 'digest/md5'
ENV["JAVA_HOME"] ||= "/usr/lib/jvm/java-7-openjdk" 
# TODO store descriptors in mongodb

module OpenTox

  module Algorithm 
    
    # Class for descriptor calculations
    class Descriptor 
      include OpenTox

      JAVA_DIR = File.join(File.dirname(__FILE__),"..","java")
      CDK_JAR = Dir[File.join(JAVA_DIR,"cdk-*jar")].last
      JOELIB_JAR = File.join(JAVA_DIR,"joelib2.jar")
      LOG4J_JAR = File.join(JAVA_DIR,"log4j.jar")
      JMOL_JAR = File.join(JAVA_DIR,"Jmol.jar")

      obexclude = ["cansmi","cansmiNS","formula","InChI","InChIKey","s","smarts","title","L5"]
      OBDESCRIPTORS = Hash[OpenBabel::OBDescriptor.list_as_string("descriptors").split("\n").collect do |d|
        name,description = d.split(/\s+/,2)
        ["Openbabel."+name,description] unless obexclude.include? name
      end.compact.sort{|a,b| a[0] <=> b[0]}]

      cdk_desc = YAML.load(`java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptorInfo`)
      CDKDESCRIPTORS = Hash[cdk_desc.collect { |d| ["Cdk."+d[:java_class].split('.').last.sub(/Descriptor/,''), d[:description]] }.sort{|a,b| a[0] <=> b[0]}]
      CDKDESCRIPTOR_VALUES = cdk_desc.collect { |d| prefix="Cdk."+d[:java_class].split('.').last.sub(/Descriptor/,''); d[:names].collect{ |name| prefix+"."+name } }.flatten

      # exclude Hashcode (not a physchem property) and GlobalTopologicalChargeIndex (Joelib bug)
      joelibexclude = ["MoleculeHashcode","GlobalTopologicalChargeIndex"]
      # strip Joelib messages from stdout
      JOELIBDESCRIPTORS = Hash[YAML.load(`java -classpath #{JOELIB_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptorInfo | sed '0,/---/d'`).collect do |d|
        name = d[:java_class].sub(/^joelib2.feature.types./,'')
        # impossible to obtain meaningful descriptions from JOELIb, see java/JoelibDescriptors.java
        ["Joelib."+name, "no description available"] unless joelibexclude.include? name
      end.compact.sort{|a,b| a[0] <=> b[0]}] 

      DESCRIPTORS = OBDESCRIPTORS.merge(CDKDESCRIPTORS.merge(JOELIBDESCRIPTORS))
      DESCRIPTOR_VALUES = OBDESCRIPTORS.keys + CDKDESCRIPTOR_VALUES + JOELIBDESCRIPTORS.keys

      require_relative "unique_descriptors.rb"

      # Description of available descriptors
      def self.description descriptor
        lib = descriptor.split('.').first
        case lib
        when "Openbabel"
          OBDESCRIPTORS[descriptor]
        when "Cdk"
          name = descriptor.split('.')[0..-2].join('.')
          CDKDESCRIPTORS[name]
        when "Joelib"
          JOELIBDESCRIPTORS[descriptor]
        when "lookup"
          "Read feature values from a dataset"
        end
      end

      # Match an array of smarts features 
      def self.smarts_match compounds, smarts_features, count=false
        bad_request_error "Compounds for smarts_match are empty" unless compounds
        bad_request_error "Smarts features for smarts_match are empty" unless smarts_features
        parse compounds
        @count = count
        obconversion = OpenBabel::OBConversion.new
        obmol = OpenBabel::OBMol.new
        obconversion.set_in_format('smi')
        smarts_pattern = OpenBabel::OBSmartsPattern.new
        smarts_features = [smarts_features] if smarts_features.is_a?(Feature)
        @smarts = smarts_features.collect{|f| f.smarts}
        @physchem_descriptors = nil
        @data_entries = Array.new(@compounds.size){Array.new(@smarts.size,false)}
        @compounds.each_with_index do |compound,c|
          obconversion.read_string(obmol,compound.smiles)
          @smarts.each_with_index do |smart,s|
            smarts_pattern.init(smart)
            if smarts_pattern.match(obmol)
              count ? value = smarts_pattern.get_map_list.to_a.size : value = 1
            else
              value = 0 
            end
            @data_entries[c][s] = value
          end
        end
        serialize 
      end

      # Count matches of an array with smarts features 
      def self.smarts_count compounds, smarts
        # TODO: non-overlapping matches?
        smarts_match compounds,smarts,true
      end

      # Calculate physchem descriptors
      # @param [OpenTox::Compound,Array,OpenTox::Dataset] input object, either a compound, an array of compounds or a dataset
      def self.physchem compounds, descriptors=UNIQUEDESCRIPTORS
        parse compounds
        @data_entries = Array.new(@compounds.size){[]}
        @descriptors = descriptors
        @smarts = nil
        @physchem_descriptors = [] # CDK may return more than one result per descriptor, they are stored as separate features
        des = {}
        @descriptors.each do |d|
          lib, descriptor = d.split(".",2)
          lib = lib.downcase.to_sym
          des[lib] ||= []
          des[lib] << descriptor
        end
        des.each do |lib,descriptors|
          send(lib, descriptors)
        end
        serialize
      end

      def self.openbabel descriptors
        $logger.debug "compute #{descriptors.size} openbabel descriptors for #{@compounds.size} compounds"
        obdescriptors = descriptors.collect{|d| OpenBabel::OBDescriptor.find_type d}
        obmol = OpenBabel::OBMol.new
        obconversion = OpenBabel::OBConversion.new
        obconversion.set_in_format 'smi'
        last_feature_idx = @physchem_descriptors.size
        @compounds.each_with_index do |compound,c|
          obconversion.read_string obmol, compound.smiles
          obdescriptors.each_with_index do |descriptor,d|
            @data_entries[c][d+last_feature_idx] = fix_value(descriptor.predict(obmol))
          end
        end
        @physchem_descriptors += descriptors.collect{|d| "Openbabel.#{d}"}
      end

      def self.java_descriptors descriptors, lib
        $logger.debug "compute #{descriptors.size} cdk descriptors for #{@compounds.size} compounds"
        sdf = sdf_3d 
        # use java system call (rjb blocks within tasks)
        # use Tempfiles to avoid "Argument list too long" error 
        case lib
        when "cdk"
          run_cmd "java -classpath #{CDK_JAR}:#{JAVA_DIR}  CdkDescriptors #{sdf} #{descriptors.join(" ")}"
        when "joelib"
          run_cmd "java -classpath #{JOELIB_JAR}:#{JMOL_JAR}:#{LOG4J_JAR}:#{JAVA_DIR}  JoelibDescriptors  #{sdf} #{descriptors.join(' ')}"
        end
        last_feature_idx = @physchem_descriptors.size
        YAML.load_file("#{sdf}#{lib}.yaml").each_with_index do |calculation,i|
          # TODO create warnings
          #$logger.error "Descriptor calculation failed for compound #{@compounds[i].inchi}." if calculation.empty?
          # CDK Descriptors may calculate multiple values, they are stored in separate features
          @physchem_descriptors += calculation.keys if i == 0
          calculation.keys.each_with_index do |name,j|
            @data_entries[i][j+last_feature_idx] = fix_value(calculation[name])
          end
        end
        FileUtils.rm "#{sdf}#{lib}.yaml"
      end

      def self.cdk descriptors
        java_descriptors descriptors, "cdk"
      end

      def self.joelib descriptors
        java_descriptors descriptors, "joelib"
      end

      def self.lookup compounds, features, dataset
        parse compounds
        fingerprint = []
        compounds.each do |compound|
          fingerprint << []
          features.each do |feature|
          end
        end
      end

      def self.run_cmd cmd
        cmd = "#{cmd} 2>&1"
        $logger.debug "running external cmd: '#{cmd}'"
        p = IO.popen(cmd) do |io|
          while line = io.gets
            $logger.debug "> #{line.chomp}"
          end
          io.close
          raise "external cmd failed '#{cmd}' (see log file for error msg)" unless $?.to_i == 0
        end
      end

      def self.sdf_3d 
        # TODO check if 3d sdfs are stored in GridFS
        sdf = ""
        @compounds.each do |compound|
          sdf << compound.sdf
        end
        sdf_file = "/tmp/#{SecureRandom.uuid}.sdf"
        File.open(sdf_file,"w+"){|f| f.print sdf}
        sdf_file
      end

      def self.parse compounds
        @input_class = compounds.class.to_s
        case @input_class
        when "OpenTox::Compound"
          @compounds = [compounds]
        when "Array"
          @compounds = compounds
        when "OpenTox::Dataset"
          @compounds = compounds.compounds
        else
          bad_request_error "Cannot calculate descriptors for #{compounds.class} objects."
        end
      end

      def self.serialize
        @data_entries.collect!{|de| de.collect{|v| v.round(5) unless v.nil?}}
        case @input_class
        when "OpenTox::Compound"
          @data_entries.first
        when "Array"
          @data_entries
        when "OpenTox::Dataset"
          dataset = OpenTox::DescriptorDataset.new(:compound_ids => @compounds.collect{|c| c.id})
          if @smarts
            dataset.feature_ids = @smarts.collect{|smart| Smarts.find_or_create_by(:smarts => smart).id}
            @count ? algo = "count" : algo = "match"
            dataset.feature_calculation_algorithm = "#{self}.smarts_#{algo}"
            
          elsif @physchem_descriptors
            dataset.feature_ids = @physchem_descriptors.collect{|d| PhysChemDescriptor.find_or_create_by(:name => d, :creator => __FILE__).id}
            dataset.data_entries = @data_entries
            dataset.feature_calculation_algorithm = "#{self}.physchem"
            #TODO params?
          end
          dataset.save_all
          dataset
        end
      end

      def self.fix_value val
        val = val.first if val.is_a? Array and val.size == 1
        val = nil if val == "NaN"
        if val.numeric?
          val = Float(val)
          val = nil if val.nan? or val.infinite?
        end
        val
      end
      private_class_method :sdf_3d, :fix_value, :parse, :run_cmd, :serialize
    end
  end
end
