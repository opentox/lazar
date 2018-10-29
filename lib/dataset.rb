require 'csv'
require 'tempfile'
require 'digest/md5'

module OpenTox

  # Collection of substances and features
  class Dataset

    field :data_entries, type: Array, default: [] #substance,feature,value
    field :warnings, type: Array, default: [] 
    field :source, type: String
    field :md5, type: String

    # Readers

    # Get all compounds
    # @return [Array<OpenTox::Compound>]
    def compounds
      substances.select{|s| s.is_a? Compound}
    end

    # Get all nanoparticles
    # @return [Array<OpenTox::Nanoparticle>]
    def nanoparticles
      substances.select{|s| s.is_a? Nanoparticle}
    end

    # Get all substances
    # @return [Array<OpenTox::Substance>]
    def substances
      @substances ||= data_entries.collect{|row| OpenTox::Substance.find row[0]}.uniq
      @substances
    end

    # Get all features
    # @return [Array<OpenTox::Feature>]
    def features
      @features ||= data_entries.collect{|row| OpenTox::Feature.find(row[1])}.uniq
      @features
    end

    # Get all values for a given substance and feature
    # @param [OpenTox::Substance,BSON::ObjectId] substance or substance id
    # @param [OpenTox::Feature,BSON::ObjectId] feature or feature id
    # @return [Array<TrueClass,FalseClass,Float>] values
    def values substance,feature
      substance = substance.id if substance.is_a? Substance
      feature = feature.id if feature.is_a? Feature
      data_entries.select{|row| row[0] == substance and row[1] == feature}.collect{|row| row[2]}
    end

    # Get OriginalId features
    # @return [Array<OpenTox::OriginalId>] original ID features (merged datasets may have multiple original IDs)
    def original_id_features
      features.select{|f| f.is_a?(OriginalId)}
    end

    # Get OriginalSmiles features
    # @return [Array<OpenTox::OriginalSmiles>] original smiles features (merged datasets may have multiple original smiles)
    def original_smiles_features
      features.select{|f| f.is_a?(OriginalSmiles)}
    end

    # Get Warnings features
    # @return [Array<OpenTox::Warnings>] warnings features (merged datasets may have multiple warnings)
    def warnings_features
      features.select{|f| f.is_a?(Warnings)}
    end

    # Get nominal and numeric bioactivity features
    # @return [Array<OpenTox::NominalBioActivity,OpenTox::NumericBioActivity>]
    def bioactivity_features
      features.select{|f| f._type.match(/BioActivity/)}
    end

    # Get nominal and numeric bioactivity features
    # @return [Array<OpenTox::NominalBioActivity,OpenTox::NumericBioActivity>]
    def transformed_bioactivity_features
      features.select{|f| f._type.match(/Transformed.*BioActivity/)}
    end

    # Get nominal and numeric substance property features
    # @return [Array<OpenTox::NominalSubstanceProperty,OpenTox::NumericSubstanceProperty>]
    def substance_property_features
      features.select{|f| f._type.match("SubstanceProperty")}
    end

    # Writers

    # Add a value for a given substance and feature
    # @param [OpenTox::Substance,BSON::ObjectId,String] substance or substance id
    # @param [OpenTox::Feature,BSON::ObjectId,String] feature or feature id
    # @param [TrueClass,FalseClass,Float]
    def add(substance,feature,value)
      substance = substance.id if substance.is_a? Substance
      feature = feature.id if feature.is_a? Feature
      data_entries << [substance,feature,value] if substance and feature and value
    end

    # Parsers
    
    # Create a dataset from CSV file
    # @param [File] Input file with the following format:
    #   - ID column (optional): header containing "ID" string, arbitrary ID values
    #   - SMILES/InChI column: header indicating "SMILES" or "InChI", Smiles or InChI strings
    #   - one or more properties column(s): header with property name(s), property values
    #     files with a single property column are read as BioActivities (i.e. dependent variable)
    #     files with multiple property columns are read as SubstanceProperties (i.e. independent variables)
    # @return [OpenTox::Dataset]
    def self.from_csv_file file
      md5 = Digest::MD5.hexdigest(File.read(file)) # use hash to identify identical files
      dataset = self.find_by(:md5 => md5)
      if dataset
        $logger.debug "Found #{file} in the database (id: #{dataset.id}, md5: #{dataset.md5}), skipping import."
      else
        $logger.debug "Parsing #{file}."
        table = nil
        sep = ","
        ["\t",";"].each do |s| # guess alternative CSV separator
          if File.readlines(file).first.match(/#{s}/)
            sep = s
            break
          end
        end
        table = CSV.read file, :col_sep => sep, :skip_blanks => true, :encoding => 'windows-1251:utf-8'
        if table
          dataset = self.new(:source => file, :name => File.basename(file,".*"), :md5 => md5)
          dataset.parse_table table
        else
          bad_request_error "#{file} is not a valid CSV/TSV file. Could not find "," ";" or TAB as column separator."
        end
      end
      dataset
    end

    # Create a dataset from SDF file 
    #   files with a single data field are read as BioActivities (i.e. dependent variable)
    #   files with multiple data fields are read as SubstanceProperties (i.e. independent variable)
    # @param [File] 
    # @return [OpenTox::Dataset]
    def self.from_sdf_file file
      md5 = Digest::MD5.hexdigest(File.read(file)) # use hash to identify identical files
      dataset = self.find_by(:md5 => md5)
      if dataset
        $logger.debug "Found #{file} in the database (id: #{dataset.id}, md5: #{dataset.md5}), skipping import."
      else
        $logger.debug "Parsing #{file}."

        dataset = self.new(:source => file, :name => File.basename(file,".*"), :md5 => md5)
        original_id = OriginalId.find_or_create_by(:dataset_id => dataset.id,:name => dataset.name+".ID")

        read_result = false
        sdf = ""
        feature_name = ""
        compound = nil
        features = {}
        table = [["ID","SMILES"]]

        File.readlines(file).each do |line|
          if line.match %r{\$\$\$\$}
            sdf << line
            id = sdf.split("\n").first.chomp
            compound = Compound.from_sdf sdf
            row = [id,compound.smiles]
            features.each do |f,v|
              table[0] << f unless table[0].include? f
              row[table[0].index(f)] = v
            end
            table << row
            sdf = ""
            features = {}
          elsif line.match /^>\s+</
            feature_name = line.match(/^>\s+<(.*)>/)[1]
            read_result = true
          else
            if read_result
              value = line.chomp
              features[feature_name] = value
              read_result = false
            else
              sdf << line
            end
          end
        end
        dataset.parse_table table
      end
      dataset.save
      dataset
    end

    # Create a dataset from PubChem Assay
    # @param [Integer] PubChem AssayID (AID)
    # @return [OpenTox::Dataset]
    def self.from_pubchem_aid aid
      url = File.join PUBCHEM_URI, "assay/aid/#{aid}/CSV"
      assay_metadata = JSON.parse(RestClientWrapper.get(File.join PUBCHEM_URI,"assay/aid/#{aid}/description/JSON").to_s)["PC_AssayContainer"][0]["assay"]["descr"]
      name = assay_metadata["name"].gsub(/\s+/,"_")
      csv = CSV.parse(RestClientWrapper.get(url))
      csv.select!{|r| r[0].match /^\d/} # discard header rows
      table = [["SID","SMILES",name]]
      csv.each_slice(100) do |slice| # get SMILES in chunks
        sids = slice.collect{|s| s[1]}
        smiles = RestClientWrapper.get(File.join(PUBCHEM_URI,"compound/cid/#{sids.join(",")}/property/CanonicalSMILES/TXT")).split("\n").collect{|s| s.to_s}
        abort("Could not get SMILES for all SIDs from PubChem") unless sids.size == smiles.size
        smiles.each_with_index do |smi,i|
          table << [slice[i][1].to_s,smi.chomp,slice[i][3].to_s]
        end
      end
      dataset = self.new(:source => url, :name => name) 
      dataset.parse_table table
      dataset
    end

    # Parse data in tabular format (e.g. from csv)
    #   does a lot of guesswork in order to determine feature types
    # @param [Array<Array>] 
    def parse_table table

      # features
      feature_names = table.shift.collect{|f| f.strip}
      bad_request_error "Duplicated features in table header." unless feature_names.size == feature_names.uniq.size

      if feature_names[0] =~ /ID/i # check ID column
        original_id = OriginalId.find_or_create_by(:dataset_id => self.id,:name => feature_names.shift)
      else
        original_id = OriginalId.find_or_create_by(:dataset_id => self.id,:name => "LineID")
      end

      compound_format = feature_names.shift
      bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: SMILES, InChI." unless compound_format =~ /SMILES|InChI/i
      original_smiles = OriginalSmiles.find_or_create_by(:dataset_id => self.id) if compound_format.match(/SMILES/i)

      numeric = []
      features = []

      # guess feature types
      bioactivity = true if feature_names.size == 1

      feature_names.each_with_index do |f,i|
        original_id.name.match(/LineID$/) ? j = i+1 : j = i+2
        values = table.collect{|row| val=row[j].to_s.strip; val.blank? ? nil : val }.uniq.compact
        types = values.collect{|v| v.numeric? ? true : false}.uniq
        feature = nil
        if values.size == 0 # empty feature
        elsif  values.size > 5 and types.size == 1 and types.first == true # 5 max classes
          numeric[i] = true
          bioactivity ?  feature = NumericBioActivity.find_or_create_by(:name => f) : feature = NumericSubstanceProperty.find_or_create_by(:name => f)
        else
          numeric[i] = false
          bioactivity ?  feature = NominalBioActivity.find_or_create_by(:name => f, :accept_values => values.sort) : feature = NominalSubstanceProperty.find_or_create_by(:name => f, :accept_values => values.sort)
        end
        features << feature if feature
      end
      
      # substances and values

      all_substances = []
      table.each_with_index do |vals,i|
        original_id.name.match(/LineID$/) ? original_id_value = i+1 : original_id_value = vals.shift.strip
        identifier = vals.shift.strip
        begin
          case compound_format
          when /SMILES/i
            substance = Compound.from_smiles(identifier)
            add substance, original_smiles, identifier
          when /InChI/i
            substance = Compound.from_inchi(identifier)
          end
        rescue 
          substance = nil
        end

        if substance.nil? # compound parsers may return nil
          warnings << "Cannot parse #{compound_format} compound '#{identifier}' at line #{i+2} of #{source}, all entries are ignored."
          next
        end

        all_substances << substance
        substance.dataset_ids << self.id
        substance.dataset_ids.uniq!
        substance.save

        add substance, original_id, original_id_value 

        vals.each_with_index do |v,j|
          if v.blank?
            warnings << "Empty value for compound '#{identifier}' (#{original_id_value}) and feature '#{feature_names[j]}'."
            next
          elsif numeric[j]
            v = v.to_f
          else
            v = v.strip
          end
          add substance, features[j], v
        end
      end

      warnings_feature = Warnings.find_or_create_by(:dataset_id => id)
      all_substances.duplicates.each do |substance|
        positions = []
        all_substances.each_with_index{|c,i| positions << i+1 if !c.blank? and c.smiles and c.smiles == substance.smiles}
        all_substances.select{|s| s.smiles == substance.smiles}.each do |s|
          add s, warnings_feature, "Duplicate compound #{substance.smiles} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
        end
      end
      save
    end

    # Serialisation
    
    # Convert dataset to csv format 
    # @return [String]
    def to_csv #inchi=false
      CSV.generate() do |csv| 
        
        compound = substances.first.is_a? Compound
        f = features - original_id_features - original_smiles_features - warnings_features
        header = original_id_features.collect{|f| "ID "+Dataset.find(f.dataset_id).name}
        header += original_smiles_features.collect{|f| "SMILES "+Dataset.find(f.dataset_id).name} if compound
        compound ? header << "Canonical SMILES" : header << "Name"
        header += f.collect{|f| f.name}
        header += warnings_features.collect{|f| "Warnings "+Dataset.find(f.dataset_id).name} 
        csv << header

        substances.each do |substance|
          row = original_id_features.collect{|f| values(substance,f).join(" ")}
          row += original_smiles_features.collect{|f| values(substance,f).join(" ")} if compound
          compound ? row << substance.smiles : row << substance.name
          row += f.collect{|f| values(substance,f).join(" ")}
          row += warnings_features.collect{|f| values(substance,f).uniq.join(" ")} 
          csv << row
        end

      end
    end

    # Convert dataset to SDF format
    # @return [String] SDF string
    def to_sdf
      sdf = ""
      substances.each do |substance|
        sdf_lines = substance.sdf.sub(/\$\$\$\$\n/,"").split("\n")
        sdf_lines[0] = substance.smiles
        sdf += sdf_lines.join("\n")
        features.each do |f|
          sdf += "\n> <#{f.name}>\n"
          sdf += values(substance,f).uniq.join ","
        end
        sdf += "\n$$$$\n"
      end
      sdf
    end

    # Dataset operations

    # Merge an array of datasets 
    # @param [Array<OpenTox::Dataset>] datasets to be merged
    # @return [OpenTox::Dataset] merged dataset
    def self.merge datasets
      dataset = self.create(:source => datasets.collect{|d| d.id.to_s}.join(", "), :name => datasets.collect{|d| d.name}.uniq.join(", "))
      datasets.each do |d|
        dataset.data_entries += d.data_entries
        dataset.warnings += d.warnings
      end
      dataset.save
      dataset
    end

    # Copy a dataset
    # @return OpenTox::Dataset dataset copy
    def copy
      dataset = Dataset.new
      dataset.data_entries = data_entries
      dataset.warnings = warnings
      dataset.name = name
      dataset.source = id.to_s
      dataset.save
      dataset
    end

    # Split a dataset into n folds
    # @param [Integer] number of folds
    # @return [Array] Array with folds [training_dataset,test_dataset]
    def folds n
      len = self.substances.size
      indices = (0..len-1).to_a.shuffle
      mid = (len/n)
      chunks = []
      start = 0
      1.upto(n) do |i|
        last = start+mid
        last = last-1 unless len%n >= i
        test_idxs = indices[start..last] || []
        test_substances = test_idxs.collect{|i| substances[i]}
        training_idxs = indices-test_idxs
        training_substances = training_idxs.collect{|i| substances[i]}
        chunk = [training_substances,test_substances].collect do |substances|
          dataset = self.class.create(:name => "#{self.name} (Fold #{i-1})",:source => self.id )
          substances.each do |substance|
            substance.dataset_ids << dataset.id
            substance.dataset_ids.uniq!
            substance.save
            dataset.data_entries += data_entries.select{|row| row[0] == substance.id}
          end
          dataset.save
          dataset
        end
        start = last+1
        chunks << chunk
      end
      chunks
    end

    # Change nominal feature values
    # @param [NominalFeature] Original feature
    # @param [Hash] how to change feature values
    def map feature, map
      dataset = self.copy
      new_feature = TransformedNominalBioActivity.find_or_create_by(:name => feature.name + " (transformed)", :original_feature_id => feature.id, :transformation => map, :accept_values => map.values.sort)
      compounds.each do |c|
        values(c,feature).each { |v| dataset.add c, new_feature, map[v] }
      end
      dataset.save
      dataset
    end

    def merge_nominal_features nominal_features, maps=[]
      dataset = self.copy
      new_feature = MergedNominalBioActivity.find_or_create_by(:name => nominal_features.collect{|f| f.name}.join("/") + " (transformed)", :original_feature_id => feature.id, :transformation => map, :accept_values => map.values.sort)

      compounds.each do |c|
        if map
          values(c,feature).each { |v| dataset.add c, new_feature, map[v] }
        else
        end
      end
    end
    
    def transform # TODO
    end

    # Delete dataset
    def delete
      compounds.each{|c| c.dataset_ids.delete id.to_s}
      super
    end

  end

end
