module OpenTox

  # create default OpenTox classes
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
    end
    OpenTox.const_set klass,c
  end

end
