module OpenTox

  class Substance
    field :physchem, type: Hash, default: {}
    field :toxicities, type: Hash, default: {}
    field :dataset_ids, type: Array, default: []
  end

end

