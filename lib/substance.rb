module OpenTox

  class Substance
    field :physchem_descriptors, type: Hash, default: {}
    field :dataset_ids, type: Array, default: []
  end

end

