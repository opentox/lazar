module OpenToxError
  attr_accessor :http_code, :message, :cause
  def initialize message=nil
    message = message.to_s.gsub(/\A"|"\Z/, '') if message # remove quotes
    super message
    @http_code ||= 500
    @message = message.to_s
    @cause = cut_backtrace(caller)
    $logger.error("\n"+JSON.pretty_generate({
      :http_code => @http_code,
      :message => @message,
      :cause => @cause
    })) 
  end
  
  def cut_backtrace(trace)
    if trace.is_a?(Array)
      cut_index = trace.find_index{|line| line.match(/sinatra|minitest/)}
      cut_index ||= trace.size
      cut_index -= 1
      cut_index = trace.size-1 if cut_index < 0
      trace[0..cut_index]
    else
      trace
    end
  end

end

class RuntimeError
  include OpenToxError
end

# clutters log file with library errors 
#class NoMethodError
  #include OpenToxError
#end

module OpenTox

  class Error < RuntimeError
    include OpenToxError
    
    def initialize(code, message=nil)
      @http_code = code
      super message
    end
  end

  # OpenTox errors
  RestClientWrapper.known_errors.each do |error|
    # create error classes 
    c = Class.new Error do
      define_method :initialize do |message=nil|
        super error[:code], message
      end
    end
    OpenTox.const_set error[:class],c
    
    # define global methods for raising errors, eg. bad_request_error
    Object.send(:define_method, error[:method]) do |message|
      raise c.new(message)
    end
  end
  
end
