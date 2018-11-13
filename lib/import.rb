module OpenTox

  class Import

    def self.public_data
      # TODO clear database?
      Dir[File.join(File.dirname(__FILE__),"..","data/*csv")].each do |f|
        $logger.debug f
        Model::Validation.from_csv_file f
      end
    end
  end
end
