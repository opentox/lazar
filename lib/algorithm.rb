module OpenTox

  module Algorithm 

    # Generic method to execute algorithms
    # Algorithms should:
    #   - accept a Compound, an Array of Compounds or a Dataset as first argument
    #   - optional parameters as second argument
    #   - return an object corresponding to the input type as result (eg. Compound -> value, Array of Compounds -> Array of values, Dataset -> Dataset with values
    # @param [OpenTox::Compound,Array,OpenTox::Dataset] Input object
    # @param [Hash] Algorithm parameters
    # @return Algorithm result
    def self.run algorithm, object, parameters=nil
      bad_request_error "Cannot run '#{algorithm}' algorithm. Please provide an OpenTox::Algorithm." unless algorithm =~ /^OpenTox::Algorithm/
      klass,method = algorithm.split('.')
      parameters.nil? ?  Object.const_get(klass).send(method,object) : Object.const_get(klass).send(method,object, parameters)
    end

  end
end

