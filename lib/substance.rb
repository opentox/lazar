module OpenTox

  # Base class for substances (e.g. compunds, nanoparticles)
  class Substance
    field :properties, type: Hash, default: {}
  end

end
