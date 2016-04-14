module OpenTox

  # Ruby interface

  # create default OpenTox classes (defined in opentox-client.rb)
  # provides Mongoid's query and persistence methods
  # http://mongoid.org/en/mongoid/docs/persistence.html
  # http://mongoid.org/en/mongoid/docs/querying.html
  CLASSES.each do |klass|
    c = Class.new do
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: klass.downcase.pluralize
      field :name,  type: String
      field :source,  type: String
      field :warnings, type: Array, default: []

      def warn warning
        $logger.warn warning
        warnings << warning
      end
    end
    OpenTox.const_set klass,c
  end

end

