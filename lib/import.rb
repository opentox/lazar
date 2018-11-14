module OpenTox

  class Import

    # Import datasets from the data folder, create and validate models 
    # @return [Array<OpenTox::Model::Validation>] Validated models
    def self.public_data
      models = []
      Dir[File.join(File.dirname(__FILE__),"..","data/*csv")].each do |f|
        $logger.debug f
        m = Model::Validation.from_csv_file f
        $logger.debug "#{f} ID: #{m.id.to_s}"
        m.crossvalidations.each do |cv|
          $logger.debug cv.statistics
        end
        models << m
      end
      models
    end
  end
end
