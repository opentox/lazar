require "base64"
class Object
  # An object is blank if it's false, empty, or a whitespace string.
  # For example, "", "   ", +nil+, [], and {} are all blank.
  # @return [TrueClass,FalseClass]
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  # Is it a numeric object
  # @return [TrueClass,FalseClass]
  def numeric?
    true if Float(self) rescue false
  end

  # Returns dimension of nested arrays
  # @return [Fixnum]
  def dimension
    self.class == Array ? 1 + self[0].dimension : 0
  end
end

class Numeric
  # Convert number to percent
  # @return [Float]
  def percent_of(n)
    self.to_f / n.to_f * 100.0
  end
end

class Float
  # Round to n significant digits
  #   http://stackoverflow.com/questions/8382619/how-to-round-a-float-to-a-specified-number-of-significant-digits-in-ruby
  # @param [Fixnum]
  # @return [Float]
  def signif(n)
    Float("%.#{n}g" % self)
  end

  # Convert -10 log values to original values
  # @return [Float]
  def delog10
    10**(-1*self)
  end
end

module Enumerable
  # Get duplicates
  # @return [Array] 
  def duplicates
    inject({}) {|h,v| h[v]=h[v].to_i+1; h}.reject{|k,v| v==1}.keys
  end
  # http://stackoverflow.com/questions/2562256/find-most-common-string-in-an-array
  Enumerable.class_eval do
    def mode
      group_by do |e|
        e
      end.values.max_by(&:size).first
    end
  end
end

class String
  # Convert camel-case to underscore-case
  # @example 
  #   OpenTox::SuperModel -> open_tox/super_model
  # @return [String]
  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end

  # Convert strings to boolean values
  # @return [TrueClass,FalseClass] true or false
  def to_boolean
    return true if self == true || self =~ (/(true|t|yes|y|1)$/i)
    return false if self == false || self.nil? || self =~ (/(false|f|no|n|0)$/i)
    bad_request_error "invalid value for Boolean: \"#{self}\""
  end

end

class File
  # Get mime_type including charset using linux file command
  # @return [String]
  def mime_type
    `file -ib '#{self.path}'`.chomp
  end
end

class Array

  # Sum the size of single arrays in an array of arrays
  # @param [Array] Array of arrays
  # @return [Integer] Sum of size of array elements
  def sum_size
    self.inject(0) { |s,a|
      if a.respond_to?('size')
        s+=a.size
      else
        internal_server_error "No size available: #{a.inspect}"
      end
    }
  end

  # Check if the array has just one unique value.
  # @param [Array] Array to test.
  # @return [TrueClass,FalseClass] 
  def zero_variance?
    return self.uniq.size == 1
  end

  # Get the median of an array
  # @return [Numeric]
  def median
    sorted = self.sort
    len = sorted.length
    (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
  end

  # Get the mean of an array
  # @return [Numeric]
  def mean
    self.compact.inject{ |sum, el| sum + el }.to_f / self.compact.size
  end

  # Get the variance of an array
  # @return [Numeric]
  def sample_variance
    m = self.mean
    sum = self.compact.inject(0){|accum, i| accum +(i-m)**2 }
    sum/(self.compact.length - 1).to_f
  end

  # Get the standard deviation of an array
  # @return [Numeric]
  def standard_deviation
    Math.sqrt(self.sample_variance)
  end

  # Convert array values for R
  # @return [Array]
  def for_R
    if self.first.is_a?(String) 
      #"\"#{self.collect{|v| v.sub('[','').sub(']','')}.join(" ")}\"" # quote and remove square brackets
      "NA"
    else
      self.median
    end
  end

  # Collect array with index
  #   in analogy to each_with_index
  def collect_with_index
    result = []
    self.each_with_index do |elt, idx|
      result << yield(elt, idx)
    end
    result
  end
end

module URI

  # Is it a https connection
  # @param [String]
  # @return [TrueClass,FalseClass]
  def self.ssl? uri
    URI.parse(uri).instance_of? URI::HTTPS
  end

  # Check if a http resource exists by making a HEAD-request
  # @return [TrueClass,FalseClass]
  def self.accessible?(uri)
    parsed_uri = URI.parse(uri + (OpenTox::RestClientWrapper.subjectid ? "?subjectid=#{CGI.escape OpenTox::RestClientWrapper.subjectid}" : ""))
    http_code = URI.task?(uri) ? 600 : 400
    http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
    unless (URI.ssl? uri) == true
      http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
      request = Net::HTTP::Head.new(parsed_uri.request_uri)
      http.request(request).code.to_i < http_code
    else
      http = Net::HTTP.new(parsed_uri.host, parsed_uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      request = Net::HTTP::Head.new(parsed_uri.request_uri)
      http.request(request).code.to_i < http_code
    end
  rescue
    false
  end

  # Is the URI valid
  # @param [String]
  # @return [TrueClass,FalseClass]
  def self.valid? uri
    u = URI.parse(uri)
    u.scheme!=nil and u.host!=nil
  rescue URI::InvalidURIError
    false
  end

  # Is the URI a task URI
  # @param [String]
  def self.task? uri
    uri =~ /task/ and URI.valid? uri
  end

end
