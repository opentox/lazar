module OpenTox

  class Nanoparticle
    include OpenTox

    field :particle_id, type: String
    field :core, type: String
    field :coatings, type: Array

    #field :physchem_descriptors, type: Hash, default: {}
    #field :toxicities, type: Hash, default: {}
    field :features, type: Hash, default: {}

  end
end


