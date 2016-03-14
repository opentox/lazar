require 'csv'
require 'tempfile'

module OpenTox

  class Dataset

    # associations like has_many, belongs_to deteriorate performance
    field :feature_ids, type: Array, default: []
    field :compound_ids, type: Array, default: []
    field :data_entries, type: Array, default: []
    field :source, type: String

    # Readers

    # Get all compounds
    def compounds
      @compounds ||= self.compound_ids.collect{|id| OpenTox::Compound.find id}
      @compounds
    end

    # Get all features
    def features
      @features ||= self.feature_ids.collect{|id| OpenTox::Feature.find(id)}
      @features
    end

    # Find data entry values for a given compound and feature
    # @param compound [OpenTox::Compound] OpenTox Compound object
    # @param feature [OpenTox::Feature] OpenTox Feature object
    # @return [Array] Data entry values
    def values(compound, feature)
      rows = compound_ids.each_index.select{|r| compound_ids[r] == compound.id }
      col = feature_ids.index feature.id
      rows.collect{|row| data_entries[row][col]}
    end

    # Writers

    # Set compounds
    def compounds=(compounds)
      self.compound_ids = compounds.collect{|c| c.id}
    end

    # Set features
    def features=(features)
      self.feature_ids = features.collect{|f| f.id}
    end

    # Dataset operations

    # Split a dataset into n folds
    # @param [Integer] number of folds
    # @return [Array] Array with folds [training_dataset,test_dataset]
    def folds n
      unique_compound_data = {}
      compound_ids.each_with_index do |cid,i|
        unique_compound_data[cid] ||= []
        unique_compound_data[cid] << data_entries[i]
      end
      unique_compound_ids = unique_compound_data.keys
      len = unique_compound_ids.size
      indices = (0..len-1).to_a.shuffle
      mid = (len/n)
      chunks = []
      start = 0
      1.upto(n) do |i|
        last = start+mid
        last = last-1 unless len%n >= i
        test_idxs = indices[start..last] || []
        test_cids = test_idxs.collect{|i| unique_compound_ids[i]}
        training_idxs = indices-test_idxs
        training_cids = training_idxs.collect{|i| unique_compound_ids[i]}
        chunk = [training_cids,test_cids].collect do |unique_cids|
          cids = []
          data_entries = []
          unique_cids.each do |cid| 
            unique_compound_data[cid].each do |de|
              cids << cid
              data_entries << de
            end
          end
          dataset = self.class.new(:compound_ids => cids, :feature_ids => self.feature_ids, :data_entries => data_entries, :source => self.id )
          dataset.compounds.each do |compound|
            compound.dataset_ids << dataset.id
            compound.save
          end
          dataset
        end
        start = last+1
        chunks << chunk
      end
      chunks
    end

    # Diagnostics
    
    def duplicates feature=self.features.first
      col = feature_ids.index feature.id
      dups = {}
      compound_ids.each_with_index do |cid,i|
        rows = compound_ids.each_index.select{|r| compound_ids[r] == cid }
        values = rows.collect{|row| data_entries[row][col]}
        dups[cid] = values if values.size > 1
      end
      dups
    end

    def correlation_plot training_dataset
      # TODO: create/store svg
      R.assign "features", data_entries
      R.assign "activities", training_dataset.data_entries.collect{|de| de.first}
      R.eval "featurePlot(features,activities)"
    end

    def density_plot
      # TODO: create/store svg
      R.assign "acts", data_entries.collect{|r| r.first }#.compact
      R.eval "plot(density(-log(acts),na.rm= TRUE), main='-log(#{features.first.name})')"
    end

    # Serialisation
    
    # converts dataset to csv format including compound smiles as first column, other column headers are feature names
    # @return [String]
    def to_csv(inchi=false)
      CSV.generate() do |csv| #{:force_quotes=>true}
        csv << [inchi ? "InChI" : "SMILES"] + features.collect{|f| f.name}
        compounds.each_with_index do |c,i|
          csv << [inchi ? c.inchi : c.smiles] + data_entries[i]
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
    def self.from_csv_file file, source=nil, bioassay=true#, layout={}
      source ||= file
      name = File.basename(file,".*")
      dataset = self.find_by(:source => source, :name => name)
      if dataset
        $logger.debug "Skipping import of #{file}, it is already in the database (id: #{dataset.id})."
      else
        $logger.debug "Parsing #{file}."
        table = CSV.read file, :skip_blanks => true, :encoding => 'windows-1251:utf-8'
        dataset = self.new(:source => source, :name => name)
        dataset.parse_table table, bioassay#, layout
      end
      dataset
    end

    # parse data in tabular format (e.g. from csv)
    # does a lot of guesswork in order to determine feature types
    def parse_table table, bioassay=true

      time = Time.now

      # features
      feature_names = table.shift.collect{|f| f.strip}
      warnings << "Duplicate features in table header." unless feature_names.size == feature_names.uniq.size
      compound_format = feature_names.shift.strip
      bad_request_error "#{compound_format} is not a supported compound format. Accepted formats: SMILES, InChI." unless compound_format =~ /SMILES|InChI/i

      numeric = []
      # guess feature types
      feature_names.each_with_index do |f,i|
        metadata = {:name => f}
        values = table.collect{|row| val=row[i+1].to_s.strip; val.blank? ? nil : val }.uniq.compact
        types = values.collect{|v| v.numeric? ? true : false}.uniq
        if values.size == 0 # empty feature
        elsif  values.size > 5 and types.size == 1 and types.first == true # 5 max classes
          metadata["numeric"] = true
          numeric[i] = true
        else
          metadata["nominal"] = true
          metadata["accept_values"] = values
          numeric[i] = false
        end
        if bioassay
          if metadata["numeric"]
            feature = NumericBioAssay.find_or_create_by(metadata)
          elsif metadata["nominal"]
            feature = NominalBioAssay.find_or_create_by(metadata)
          end
        else
          metadata.merge({:measured => false, :calculated => true})
          if metadata["numeric"]
            feature = NumericFeature.find_or_create_by(metadata)
          elsif metadata["nominal"]
            feature = NominalFeature.find_or_create_by(metadata)
          end
        end
        feature_ids << feature.id if feature
      end
      
      $logger.debug "Feature values: #{Time.now-time}"
      time = Time.now

      r = -1
      compound_time = 0
      value_time = 0

      # compounds and values
      #@data_entries = [] #Array.new(table.size){Array.new(table.first.size-1)}
      self.data_entries = []

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
        unless vals.size == feature_ids.size # way cheaper than accessing features
          warnings << "Number of values at position #{i+2} is different than header size (#{vals.size} vs. #{features.size}), all entries are ignored."
          next
        end

        compound_ids << compound.id
        table.first.size == 0 ?  self.data_entries << Array.new(0) : self.data_entries << Array.new(table.first.size-1) 
        
        vals.each_with_index do |v,j|
          if v.blank?
            warnings << "Empty value for compound '#{identifier}' (row #{r+2}) and feature '#{feature_names[j]}' (column #{j+2})."
            next
          elsif numeric[j]
            v = v.to_f
          else
            v = v.strip
          end
          self.data_entries.last[j] = v
          #i = compound.feature_ids.index feature_ids[j]
          compound.features[feature_ids[j].to_s] ||= []
          compound.features[feature_ids[j].to_s] << v
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

    # Fill unset data entries 
    # @param any value
    def fill_nil_with n
      (0 .. compound_ids.size-1).each do |i|
        data_entries[i] ||= []
        (0 .. feature_ids.size-1).each do |j|
          data_entries[i][j] ||= n
        end
      end
    end

    def scale
      scaled_data_entries = Array.new(data_entries.size){Array.new(data_entries.first.size)}
      centers = []
      scales = []
      feature_ids.each_with_index do |feature_id,col| 
        R.assign "x", data_entries.collect{|de| de[col]}
        R.eval "scaled = scale(x,center=T,scale=T)"
        centers[col] = R.eval("attr(scaled, 'scaled:center')").to_ruby
        scales[col] = R.eval("attr(scaled, 'scaled:scale')").to_ruby
        R.eval("scaled").to_ruby.each_with_index do |value,row|
          scaled_data_entries[row][col] = value
        end
      end
      scaled_dataset = ScaledDataset.new(attributes)
      scaled_dataset["_id"] = BSON::ObjectId.new
      scaled_dataset["_type"] = "OpenTox::ScaledDataset"
      scaled_dataset.centers = centers
      scaled_dataset.scales = scales
      scaled_dataset.data_entries = scaled_data_entries
      scaled_dataset.save
      scaled_dataset
    end
  end

  # Dataset for lazar predictions
  class LazarPrediction < Dataset
    field :creator, type: String
    field :prediction_feature_id, type: String

    def prediction_feature
      Feature.find prediction_feature_id
    end

  end

  # Dataset for descriptors (physchem)
  class DescriptorDataset < Dataset
    field :feature_calculation_algorithm, type: String

  end

  class ScaledDataset < DescriptorDataset

    field :centers, type: Array, default: []
    field :scales, type: Array, default: []

    def original_value value, i
      value * scales[i] + centers[i]
    end
  end

  # Dataset for fminer descriptors
  class FminerDataset < DescriptorDataset
    field :training_algorithm, type: String
    field :training_dataset_id, type: BSON::ObjectId
    field :training_feature_id, type: BSON::ObjectId
    field :training_parameters, type: Hash
  end

end
