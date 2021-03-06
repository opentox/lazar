module OpenTox

  module Validation

    # Base validation class
    class Validation
      include OpenTox
      include Mongoid::Document
      include Mongoid::Timestamps
      store_in collection: "validations"
      field :name, type: String
      field :model_id, type: BSON::ObjectId
      field :nr_instances, type: Integer, default: 0
      field :nr_unpredicted, type: Integer, default: 0
      field :predictions, type: Hash, default: {}
      field :finished_at, type: Time 

      # Get model
      # @return [OpenTox::Model::Lazar]
      def model
        Model::Lazar.find model_id
      end

    end

  end

end
