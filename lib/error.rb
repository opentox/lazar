require 'open4'

# adding additional fields to Exception class to format errors according to OT-API
class RuntimeError
  attr_accessor :report, :http_code
  def initialize message
    super message
    @http_code ||= 500
    @report = OpenTox::ErrorReport.create self
    $logger.error "\n"+@report.to_turtle
  end
end

module OpenTox

  class Error < RuntimeError
    def initialize code, message
      @http_code = code
      super message
    end
  end

  # OpenTox errors
  {
    "BadRequestError" => 400,
    "NotAuthorizedError" => 401,
    "NotFoundError" => 404,
    "LockedError" => 423,
    "InternalServerError" => 500,
    "NotImplementedError" => 501,
    "ServiceUnavailableError" => 503,
    "TimeOutError" => 504,
  }.each do |klass,code|
    # create error classes 
    c = Class.new Error do
      define_method :initialize do |message|
        super code, message
      end
    end
    OpenTox.const_set klass,c
    
    # define global methods for raising errors, eg. bad_request_error
    Object.send(:define_method, klass.underscore.to_sym) do |message|
      raise c.new message
    end
  end
  
  # Errors received from RestClientWrapper calls
  class RestCallError < Error
    attr_accessor :request, :response
    def initialize request, response, message
      @request = request
      @response = response
      super 502, message
    end
  end

  class ErrorReport
    
    attr_accessor :rdf # RDF Graph
    attr_accessor :http_code # TODO: remove when task service is fixed

    def initialize 
      @rdf = RDF::Graph.new
    end

    # creates a error report object, from an ruby-exception object
    # @param [Exception] error
    def self.create error
      report = ErrorReport.new
      subject = RDF::Node.new
      report.rdf << [subject, RDF.type, RDF::OT.ErrorReport]
      message = error.message 
      errorDetails = ""
      if error.respond_to? :request
        report.rdf << [subject, RDF::OT.actor, error.request.url ]
        errorDetails += "REST paramenters:\n#{error.request.args.inspect}"
      end
      error.respond_to?(:http_code) ? statusCode = error.http_code : statusCode = 500
      if error.respond_to? :response
        statusCode = error.response.code 
        message = error.body
      end
      statusCode = error.http_code if error.respond_to? :http_code
      report.rdf << [subject, RDF::OT.statusCode, statusCode ]
      report.rdf << [subject, RDF::OT.errorCode, error.class.to_s ]
      # TODO: remove kludge for old task services
      report.http_code = statusCode
      report.rdf << [subject, RDF::OT.message , message ]

      errorDetails += "\nBacktrace:\n" + error.backtrace.short_backtrace if error.respond_to?(:backtrace) and error.backtrace 
      report.rdf << [subject, RDF::OT.errorDetails, errorDetails ]
      # TODO Error cause
      #report.rdf << [subject, OT.errorCause, error.report] if error.respond_to?(:report) and !error.report.empty?
      report
    end

    def actor=(uri)
      # TODO: test actor assignement (in opentox-server)
      subject = RDF::Query.execute(@rdf) do
          pattern [:subject, RDF.type, RDF::OT.ErrorReport]
      end.limit(1).select(:subject)
      @rdf << [subject, RDF::OT.actor, uri]
    end
    
    # define to_ and self.from_ methods for various rdf formats
    [:rdfxml,:ntriples,:turtle].each do |format|

      define_singleton_method "from_#{format}".to_sym do |rdf|
        report = ErrorReport.new
        RDF::Reader.for(format).new(rdf) do |reader|
          reader.each_statement{ |statement| report.rdf << statement }
        end
        report
      end

      send :define_method, "to_#{format}".to_sym do
        rdfxml = RDF::Writer.for(format).buffer do |writer|
          @rdf.each{|statement| writer << statement}
        end
        rdfxml
      end
    end

  end
end

# overwrite backtick operator to catch system errors
module Kernel

  # Override raises an error if _cmd_ returns a non-zero exit status.
  # Returns stdout if _cmd_ succeeds.  Note that these are simply concatenated; STDERR is not inline.
  def ` cmd
    stdout, stderr = ''
    status = Open4::popen4(cmd) do |pid, stdin_stream, stdout_stream, stderr_stream|
      stdout = stdout_stream.read
      stderr = stderr_stream.read
    end
    raise stderr.strip if !status.success?
    return stdout
  rescue Exception 
    internal_server_error "'#{cmd}' failed with: '#{$!.message}'"
  end

  alias_method :system!, :system

  def system cmd
    `#{cmd}`
    return true
  end
end

class Array
  def short_backtrace
    short = []
    each do |c|
      break if c =~ /sinatra\/base/
      short << c
    end
    short.join("\n")
  end
end
