require 'csv'
require 'tempfile'

module OpenTox

  # Collection of substances and features
  class Dataset

    field :data_entries, type: Hash, default: {}

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
      @substances ||= data_entries.keys.collect{|id| OpenTox::Substance.find id}.uniq
      @substances
    end

    # Get all features
    # @return [Array<OpenTox::Feature>]
    def features
      @features ||= data_entries.collect{|sid,data| data.keys.collect{|id| OpenTox::Feature.find(id)}}.flatten.uniq
      @features
    end

    # Get all values for a given substance and feature
    # @param [OpenTox::Substance,BSON::ObjectId,String] substance or substance id
    # @param [OpenTox::Feature,BSON::ObjectId,String] feature or feature id
    # @return [TrueClass,FalseClass,Float]
    def values substance,feature
      substance = substance.id if substance.is_a? Substance
      feature = feature.id if feature.is_a? Feature
      if data_entries[substance.to_s] and data_entries[substance.to_s][feature.to_s]
        data_entries[substance.to_s][feature.to_s]
      else
        [nil]
      end
    end

    # Writers

    # Add a value for a given substance and feature
    # @param [OpenTox::Substance,BSON::ObjectId,String] substance or substance id
    # @param [OpenTox::Feature,BSON::ObjectId,String] feature or feature id
    # @param [TrueClass,FalseClass,Float]
    def add(substance,feature,value)
      substance = substance.id if substance.is_a? Substance
      feature = feature.id if feature.is_a? Feature
      data_entries[substance.to_s] ||= {}
      data_entries[substance.to_s][feature.to_s] ||= []
      data_entries[substance.to_s][feature.to_s] << value
      #data_entries[substance.to_s][feature.to_s].uniq! if value.numeric? # assuming that identical values come from the same source
    end

    # Dataset operations

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
            dataset.data_entries[substance.id.to_s] = data_entries[substance.id.to_s] ||= {}
          end
          dataset.save
          dataset
        end
        start = last+1
        chunks << chunk
      end
      chunks
    end

    # Serialisation
    
    # Convert dataset to csv format including compound smiles as first column, other column headers are feature names
    # @return [String]
    def to_csv(inchi=false)
      CSV.generate() do |csv| 
        compound = substances.first.is_a? Compound
        if compound
          csv << [inchi ? "InChI" : "SMILES"] + features.collect{|f| f.name}
        else
          csv << ["Name"] + features.collect{|f| f.name}
        end
        substances.each do |substance|
          if compound
            name = (inchi ? substance.inchi : substance.smiles)
          else
            name = substance.name
          end
          nr_measurements = features.collect{|f| data_entries[substance.id.to_s][f.id.to_s].size if data_entries[substance.id.to_s][f.id.to_s]}.compact.uniq

          if nr_measurements.size > 1
            warn "Unequal number of measurements (#{nr_measurements}) for '#{name}'. Skipping entries."
          else
            (0..nr_measurements.first-1).each do |i|
              row = [name]
              features.each do |f|
                values(substance,f) ? row << values(substance,f)[i] : row << ""
              end
              csv << row
            end
          end
        end
      end
    end

    # Convert dataset to SDF file
    # @return [String]
    def to_sdf
      substances.each do |substance|
        puts substance.sdf.sub(/\$\$\$\$\n/,"")
        features.each do |f|
          puts "> <#{f.name}>"
          puts values(substance,f).uniq.join ","
          puts "\n$$$$"
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
    # @param [File] 
    # @param [TrueClass,FalseClass] accept or reject empty values
    # @return [OpenTox::Dataset]
    def self.from_csv_file file, accept_empty_values=false
      source = file
      name = File.basename(file,".*")
      dataset = self.find_by(:source => source, :name => name)
      if dataset
        $logger.debug "Skipping import of #{file}, it is already in the database (id: #{dataset.id})."
      else
        $logger.debug "Parsing #{file}."
        table = CSV.read file, :skip_blanks => true, :encoding => 'windows-1251:utf-8'
        dataset = self.new(:source => source, :name => name)
        dataset.parse_table table, accept_empty_values
      end
      dataset
    end

    # Parse data in tabular format (e.g. from csv)
    #   does a lot of guesswork in order to determine feature types
    # @param [Array<Array>] 
    # @param [TrueClass,FalseClass] accept or reject empty values
    def parse_table table, accept_empty_values

      # features
      feature_names = table.shift.collect{|f| f.strip}
      warnings << "Duplicated features in table header." unless feature_names.size == feature_names.uniq.size
      compound_format = feature_names.shift.strip
      bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: SMILES, InChI." unless compound_format =~ /SMILES|InChI/i
      numeric = []
      features = []
      # guess feature types
      feature_names.each_with_index do |f,i|
        metadata = {:name => f}
        values = table.collect{|row| val=row[i+1].to_s.strip; val.blank? ? nil : val }.uniq.compact
        types = values.collect{|v| v.numeric? ? true : false}.uniq
        feature = nil
        if values.size == 0 # empty feature
        elsif  values.size > 5 and types.size == 1 and types.first == true # 5 max classes
          numeric[i] = true
          feature = NumericFeature.find_or_create_by(metadata)
        else
          metadata["accept_values"] = values
          numeric[i] = false
          feature = NominalFeature.find_or_create_by(metadata)
        end
        features << feature if feature
      end
      
      # substances and values

      all_substances = []
      table.each_with_index do |vals,i|
        identifier = vals.shift.strip
        warn "No feature values for compound at line #{i+2} of #{source}." if vals.compact.empty? and !accept_empty_values
        begin
          case compound_format
          when /SMILES/i
            substance = OpenTox::Compound.from_smiles(identifier)
          when /InChI/i
            substance = OpenTox::Compound.from_inchi(identifier)
          end
        rescue 
          substance = nil
        end
        if substance.nil? # compound parsers may return nil
          warn "Cannot parse #{compound_format} compound '#{identifier}' at line #{i+2} of #{source}, all entries are ignored."
          next
        end
        all_substances << substance
        substance.dataset_ids << self.id
        substance.dataset_ids.uniq!
        substance.save
          
        unless vals.size == features.size 
          warn "Number of values at position #{i+2} is different than header size (#{vals.size} vs. #{features.size}), all entries are ignored."
          next
        end

        vals.each_with_index do |v,j|
          if v.blank?
            warn "Empty value for compound '#{identifier}' and feature '#{feature_names[i]}'."
            next
          elsif numeric[j]
            v = v.to_f
          else
            v = v.strip
          end
          add substance, features[j], v
        end
        data_entries[substance.id.to_s] = {} if vals.empty? and accept_empty_values
      end
      all_substances.duplicates.each do |substance|
        positions = []
        all_substances.each_with_index{|c,i| positions << i+1 if !c.blank? and c.inchi and c.inchi == substance.inchi}
        warn "Duplicate compound #{substance.smiles} at rows #{positions.join(', ')}. Entries are accepted, assuming that measurements come from independent experiments." 
      end
      save
    end

    # Delete dataset
    def delete
      compounds.each{|c| c.dataset_ids.delete id.to_s}
      super
    end

  end

  # Dataset for lazar predictions
  class LazarPrediction #< Dataset
    field :creator, type: String
    field :prediction_feature_id, type: BSON::ObjectId
    field :predictions, type: Hash, default: {}

    # Get prediction feature
    # @return [OpenTox::Feature]
    def prediction_feature
      Feature.find prediction_feature_id
    end

    # Get all compounds
    # @return [Array<OpenTox::Compound>]
    def compounds
      substances.select{|s| s.is_a? Compound}
    end

    # Get all substances
    # @return [Array<OpenTox::Substance>]
    def substances
      predictions.keys.collect{|id| Substance.find id}
    end

  end

end
