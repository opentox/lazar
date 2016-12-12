module OpenTox

  module Algorithm 

    def self.run algorithm, parameters=nil
      klass,method = algorithm.split('.')
      Object.const_get(klass).send(method,parameters) 
    end

  end
end

