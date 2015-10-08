module OpenTox
  
  class RestClientWrapper
    
    attr_accessor :request, :response

    @@subjectid = nil

    def self.subjectid=(subjectid)
      @@subjectid = subjectid
    end

    def self.subjectid
      @@subjectid
    end

    # REST methods 
    # Raises OpenTox::Error if call fails (rescued in overwrite.rb -> halt 502)
    # Does not wait for task to finish and returns task uri
    # @param [String] destination URI
    # @param [optional,Hash|String] Payload data posted to the service
    # @param [optional,Hash] Headers with params like :accept, :content_type, :subjectid, :verify_ssl
    # @return [RestClient::Response] REST call response 
    [:head,:get,:post,:put,:delete].each do |method|

      define_singleton_method method do |uri,payload={},headers={},waiting_task=nil|

        # check input
        bad_request_error "Headers are not a hash: #{headers.inspect}", uri unless headers==nil or headers.is_a?(Hash) 
        headers[:subjectid] ||= @@subjectid
        bad_request_error "Invalid URI: '#{uri}'", uri unless URI.valid? uri
        #resource_not_found_error "URI '#{uri}' not found.", uri unless URI.accessible?(uri, @subjectid) unless URI.ssl?(uri)
        # make sure that no header parameters are set in the payload
        [:accept,:content_type,:subjectid].each do |header|
          if defined? $aa || URI(uri).host == URI($aa[:uri]).host
          else
            bad_request_error "#{header} should be submitted in the headers", uri if payload and payload.is_a?(Hash) and payload[header]
          end
        end
      
        # create request
        args={}
        args[:method] = method
        args[:url] = uri
        args[:verify_ssl] = 0 if headers[:verify_ssl].nil? || headers[:verify_ssl].empty?
        args[:timeout] = 1800
        args[:payload] = payload
        headers.each{ |k,v| headers.delete(k) if v==nil } if headers #remove keys with empty values, as this can cause problems
        args[:headers] = headers

        $logger.debug "post to #{uri} with params #{payload.inspect.to_s[0..1000]}" if method.to_s=="post"
        
        @request = RestClient::Request.new(args)
        # ignore error codes from Task services (may return error codes >= 400 according to API, which causes exceptions in RestClient and RDF::Reader)
        @response = @request.execute do |response, request, result|
          if [301, 302, 307].include? response.code and request.method == :get
            response.follow_redirection(request, result)
          elsif response.code >= 400 and !URI.task?(uri)
            #TODO add parameters to error-report
            #parameters = request.args
            #parameters[:headers][:subjectid] = "REMOVED" if parameters[:headers] and parameters[:headers][:subjectid]
            #parameters[:url] = parameters[:url].gsub(/(http|https|)\:\/\/[a-zA-Z0-9\-]+\:[a-zA-Z0-9]+\@/, "REMOVED@") if parameters[:url]
            #message += "\nREST parameters:\n#{parameters.inspect}" 
            error = known_errors.collect{|e| e if e[:code] == response.code}.compact.first
            begin # errors are returned as error reports in json, try to parse
              # TODO: may be the reason for failure of task.rb -n test_11_wait_for_error_task
              content = JSON.parse(response)
              msg = content["message"].to_s
              cause = content["errorCause"].to_s
              raise if msg.size==0 && cause.size==0 # parsing failed
            rescue # parsing error failed, use complete content as message
              msg = "Could not parse error response from rest call '#{method}' to '#{uri}':\n#{response}"
              cause = nil
            end
            Object.method(error[:method]).call msg, uri, cause # call error method
          else
            response
          end
        end
      end
    end

    #@return [Array] of hashes with error code, method and class
    def self.known_errors
      errors = []
      RestClient::STATUSES.each do |code,k|
        if code >= 400
          method = k.underscore.gsub(/ |'/,'_')
          method += "_error" unless method.match(/_error$/)
          klass = method.split("_").collect{|s| s.capitalize}.join("")
          errors << {:code => code, :method => method.to_sym, :class => klass}
        end
      end
      errors
    end

  end
end
