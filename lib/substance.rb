module OpenTox

  class Substance
    field :properties, type: Hash, default: {}
    field :dataset_ids, type: Array, default: []
  end

end
