module OpenTox

  module Validation

    class Validation
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "validations"
      field :name, type: String
      field :model_id, type: BSON::ObjectId
      field :nr_instances, type: Integer
      field :nr_unpredicted, type: Integer
      field :predictions, type: Hash
      field :finished_at, type: Time 

      def model
        Model::Lazar.find model_id
      end

    end

  end

end
