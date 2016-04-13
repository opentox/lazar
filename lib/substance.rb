module OpenTox

  class Substance
    include OpenTox
    include Mongoid::Document
    include Mongoid::Timestamps
  end

end

