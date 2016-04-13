require 'csv'
require 'tempfile'

module OpenTox

  class Dataset

    field :data_entries, type: Hash, default: {}

    # Readers

    def compounds
      substances.select{|s| s.is_a? Compound}
    end

    # Get all substances
    def substances
      @substances ||= data_entries.keys.collect{|id| OpenTox::Substance.find id}
      @substances
    end

    # Get all features
    def features
      @features ||= data_entries.collect{|cid,f| f.first}.flatten.uniq.collect{|id| OpenTox::Feature.find(id)}
      @features
    end

    # Find data entry values for a given compound and feature
    # @param compound [OpenTox::Compound] OpenTox Compound object
    # @param feature [OpenTox::Feature] OpenTox Feature object
    # @return [Array] Data entry values
    def values(compound, feature)
      data_entries[compound.id.to_s][feature.id.to_s]
    end

    # Writers

    # Set compounds
    def compounds=(compounds)
      self.substance_ids = compounds.collect{|c| c.id}
    end

    # Set features
    #def features=(features)
      #self.feature_ids = features.collect{|f| f.id}
    #end

    # Dataset operations

    # Split a dataset into n folds
    # @param [Integer] number of folds
    # @return [Array] Array with folds [training_dataset,test_dataset]
    def folds n
      substance_ids = data_entries.keys
      len = substance_ids.size
      indices = (0..len-1).to_a.shuffle
      mid = (len/n)
      chunks = []
      start = 0
      1.upto(n) do |i|
        last = start+mid
        last = last-1 unless len%n >= i
        test_idxs = indices[start..last] || []
        test_cids = test_idxs.collect{|i| substance_ids[i]}
        training_idxs = indices-test_idxs
        training_cids = training_idxs.collect{|i| substance_ids[i]}
        chunk = [training_cids,test_cids].collect do |cids|
          new_data_entries = {}
          cids.each do |cid| 
            data_entries[cid].each do |f,v|
              new_data_entries[cid] ||= {}
              new_data_entries[cid][f] = v
            end
          end
          dataset = self.class.new(:data_entries => new_data_entries, :source => self.id )
          dataset.compounds.each do |compound|
            compound.dataset_ids << dataset.id
            compound.save
          end
          dataset.save
          dataset
        end
        start = last+1
        chunks << chunk
      end
      chunks
    end

    # Diagnostics
    
    def duplicates feature=self.features.first
      data_entries.select{|sid,f| f[feature.id].size > 1}
    end

    # Serialisation
    
    # converts dataset to csv format including compound smiles as first column, other column headers are feature names
    # @return [String]
    def to_csv(inchi=false)
      CSV.generate() do |csv| 
        csv << [inchi ? "InChI" : "SMILES"] + features.collect{|f| f.name}
        data_entries.each do |sid,f|
          substance = Substance.find cid
          features.each do |feature|
            f[feature.id].each do |v|
              csv << [inchi ? substance.inchi : substance.smiles , v]
            end
          end
        end
      end
    end

    # Parsers

    # Create a dataset from file (csv,sdf,...)
    # @param filename [String]
    # @return [String] dataset uri
    # TODO
    #def self.from_sdf_file
    #end
    
    # Create a dataset from CSV file
    # TODO: document structure
    def self.from_csv_file file, source=nil
      source ||= file
      name = File.basename(file,".*")
      dataset = self.find_by(:source => source, :name => name)
      if dataset
        $logger.debug "Skipping import of #{file}, it is already in the database (id: #{dataset.id})."
      else
        $logger.debug "Parsing #{file}."
        table = CSV.read file, :skip_blanks => true, :encoding => 'windows-1251:utf-8'
        dataset = self.new(:source => source, :name => name)
        dataset.parse_table table
      end
      dataset
    end

    # parse data in tabular format (e.g. from csv)
    # does a lot of guesswork in order to determine feature types
    def parse_table table

      time = Time.now

      # features
      feature_names = table.shift.collect{|f| f.strip}
      warnings << "Duplicated features in table header." unless feature_names.size == feature_names.uniq.size
      compound_format = feature_names.shift.strip
      # TODO nanoparticles
      bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: SMILES, InChI." unless compound_format =~ /SMILES|InChI/i

      numeric = []
      # guess feature types
      feature_names.each_with_index do |f,i|
        metadata = {:name => f}
        values = table.collect{|row| val=row[i+1].to_s.strip; val.blank? ? nil : val }.uniq.compact
        types = values.collect{|v| v.numeric? ? true : false}.uniq
        feature = nil
        if values.size == 0 # empty feature
        elsif  values.size > 5 and types.size == 1 and types.first == true # 5 max classes
          metadata["numeric"] = true
          numeric[i] = true
          feature = NumericFeature.find_or_create_by(metadata)
        else
          metadata["nominal"] = true
          metadata["accept_values"] = values
          numeric[i] = false
          feature = NominalFeature.find_or_create_by(metadata)
        end
        @features ||= []
        @features << feature if feature
      end
      
      $logger.debug "Feature values: #{Time.now-time}"
      time = Time.now

      r = -1
      compound_time = 0
      value_time = 0

      # compounds and values

      table.each_with_index do |vals,i|
        ct = Time.now
        identifier = vals.shift.strip
        warnings << "No feature values for compound at position #{i+2}." if vals.compact.empty?
        begin
          case compound_format
          when /SMILES/i
            compound = OpenTox::Compound.from_smiles(identifier)
          when /InChI/i
            compound = OpenTox::Compound.from_inchi(identifier)
          # TODO nanoparticle
          end
        rescue 
          compound = nil
        end
        if compound.nil?
          # compound parsers may return nil
          warnings << "Cannot parse #{compound_format} compound '#{identifier}' at position #{i+2}, all entries are ignored."
          next
        end
        compound.dataset_ids << self.id unless compound.dataset_ids.include? self.id
        compound_time += Time.now-ct
          
        r += 1
        unless vals.size == @features.size 
          warnings << "Number of values at position #{i+2} is different than header size (#{vals.size} vs. #{features.size}), all entries are ignored."
          next
        end

        vals.each_with_index do |v,j|
          if v.blank?
            warnings << "Empty value for compound '#{identifier}' (row #{r+2}) and feature '#{feature_names[j]}' (column #{j+2})."
            next
          elsif numeric[j]
            v = v.to_f
          else
            v = v.strip
          end
          self.data_entries[compound.id.to_s] ||= {}
          self.data_entries[compound.id.to_s][@features[j].id.to_s] ||= []
          self.data_entries[compound.id.to_s][@features[j].id.to_s] << v
          compound.features[@features[j].id.to_s] ||= []
          compound.features[@features[j].id.to_s] << v
          compound.save
        end
      end
      compounds.duplicates.each do |compound|
        positions = []
        compounds.each_with_index{|c,i| positions << i+1 if !c.blank? and c.inchi and c.inchi == compound.inchi}
        warnings << "Duplicate compound #{compound.smiles} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
      end
      
      $logger.debug "Value parsing: #{Time.now-time} (Compound creation: #{compound_time})"
      time = Time.now
      save
      $logger.debug "Saving: #{Time.now-time}"

    end

  end

  # Dataset for lazar predictions
  class LazarPrediction #< Dataset
    field :creator, type: String
    field :prediction_feature_id, type: BSON::ObjectId
    field :predictions, type: Hash, default: {}

    def prediction_feature
      Feature.find prediction_feature_id
    end

    def compounds
      substances.select{|s| s.is_a? Compound}
    end

    def substances
      predictions.keys.collect{|id| Substance.find id}
    end

  end

end
