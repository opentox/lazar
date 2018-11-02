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
