require "base64"
class Object
  # An object is blank if it's false, empty, or a whitespace string.
  # For example, "", "   ", +nil+, [], and {} are all blank.
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end

  def numeric?
    true if Float(self) rescue false
  end

  # Returns dimension of nested arrays
  def dimension
    self.class == Array ? 1 + self[0].dimension : 0
  end
end

class Numeric
  def percent_of(n)
    self.to_f / n.to_f * 100.0
  end
end

class Float
  # round to significant digits
  # http://stackoverflow.com/questions/8382619/how-to-round-a-float-to-a-specified-number-of-significant-digits-in-ruby
  def signif(signs)
    Float("%.#{signs}g" % self)
  end
end

module Enumerable
  # @return [Array] only the duplicates of an enumerable
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
  # @return [String] converts camel-case to underscore-case (OpenTox::SuperModel -> open_tox/super_model)
  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end

  # convert strings to boolean values
  # @return [TrueClass,FalseClass] true or false
  def to_boolean
    return true if self == true || self =~ (/(true|t|yes|y|1)$/i)
    return false if self == false || self.nil? || self =~ (/(false|f|no|n|0)$/i)
    bad_request_error "invalid value for Boolean: \"#{self}\""
  end

end

class File
  # @return [String] mime_type including charset using linux cmd command
  def mime_type
    `file -ib '#{self.path}'`.chomp
  end
end

class Array

  # Sum up the size of single arrays in an array of arrays
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

  # For symbolic features
  # @param [Array] Array to test.
  # @return [Boolean] Whether the array has just one unique value.
  def zero_variance?
    return self.uniq.size == 1
  end

  def median
    sorted = self.sort
    len = sorted.length
    (sorted[(len - 1) / 2] + sorted[len / 2]) / 2.0
  end

  def mean
    self.inject{ |sum, el| sum + el }.to_f / self.size
  end

  def sample_variance
    m = self.mean
    sum = self.inject(0){|accum, i| accum +(i-m)**2 }
    sum/(self.length - 1).to_f
  end

  def standard_deviation
    Math.sqrt(self.sample_variance)
  end

end

module URI

  def self.ssl? uri
    URI.parse(uri).instance_of? URI::HTTPS
  end

  # @return [Boolean] checks if resource exists by making a HEAD-request
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

  def self.valid? uri
    u = URI.parse(uri)
    u.scheme!=nil and u.host!=nil
  rescue URI::InvalidURIError
    false
  end

  def self.task? uri
    uri =~ /task/ and URI.valid? uri
  end

end
