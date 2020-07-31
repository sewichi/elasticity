module Elasticity

  class MissingKeyError < StandardError;
  end

  class AwsRequest

    SERVICE_NAME = 'elasticmapreduce'

    attr_reader :access_key
    attr_reader :secret_key
    attr_reader :session_token
    attr_reader :host
    attr_reader :protocol

    # Supported values for options:
    #  :region - AWS region (e.g. us-west-1)
    #  :secure - true or false, default true.
    def initialize(access=nil, secret=nil, options={})
      @access_key = get_access_key(access)
      @secret_key = get_secret_key(secret)
      @session_token = get_session_token(options[:session_token])
      @region = {:region => 'us-east-1'}.merge(options)[:region]
      @host = "elasticmapreduce.#@region.amazonaws.com"
      @protocol = {:secure => true}.merge(options)[:secure] ? 'https' : 'http'
      @timestamp = Time.now.utc
    end

    def headers
      signer = Aws::Sigv4::Signer.new(
        service: 'elasticmapreduce',
        region: @region,
        credentials: Aws::Credentials.new(@access_key, @secret_key, @session_token)
      )
      signature = signer.sign_request({
        http_method: 'POST',
        url: '/',
        headers: headers_to_sign(),
        body: payload
      })
      headers_to_sign().merge(signature.headers)
    end

    def payload
      ruby_params = AwsRequest.convert_ruby_to_aws_v4(@ruby_service_hash, true)
      ruby_params.to_json
    end

    def host
      "elasticmapreduce.#{@region}.amazonaws.com"
    end

    def headers_to_sign
      headers = {
        'content-type' => 'application/x-amz-json-1.1',
        'host' => host,
        'user-agent' => "elasticity/#{Elasticity::VERSION}",
        'x-amz-date' => @timestamp.strftime('%Y%m%dT%H%M%SZ'),
        'x-amz-target' => "ElasticMapReduce.#{@operation}",
      }
      if !@session_token.nil?
        headers['x-amz-security-token'] = @session_token
      end
      headers
    end

    def submit(ruby_params)
      @operation = ruby_params[:operation]
      @ruby_service_hash = ruby_params
      begin
        RestClient.post("#@protocol://#@host", payload, headers)
      rescue RestClient::BadRequest => e
        raise ArgumentError, "AWS parsed error response: #{AwsRequest.parse_error_response(e.http_body)}\n\n" +
                             "AWS raw http response: #{e.http_body}\n\nParams:#{ruby_params}"
      end
    end

    def ==(other)
      return false unless other.is_a? AwsRequest
      return false unless @access_key == other.access_key
      return false unless @secret_key == other.secret_key
      return false unless @host == other.host
      return false unless @protocol == other.protocol
      true
    end

    private

    def get_access_key(access)
      return access if access
      return ENV['AWS_ACCESS_KEY_ID'] if ENV['AWS_ACCESS_KEY_ID']
      raise MissingKeyError, 'Please provide an access key or set AWS_ACCESS_KEY_ID.'
    end

    def get_secret_key(secret)
      return secret if secret
      return ENV['AWS_SECRET_ACCESS_KEY'] if ENV['AWS_SECRET_ACCESS_KEY']
      raise MissingKeyError, 'Please provide a secret key or set AWS_SECRET_ACCESS_KEY.'
    end

    def get_session_token(session_token)
      return session_token if session_token
      return ENV['AWS_SESSION_TOKEN'] if ENV['AWS_SESSION_TOKEN']
      return nil # Session token is optional, and is nil unless working with temporary role IAM credentials.
    end

    # Since we use the same structure as AWS, we can generate AWS param names
    # from the Ruby versions of those names (and the param nesting).
    def self.convert_ruby_to_aws(params)
      result = {}
      params.each do |key, value|
        case value
          when Array
            prefix = "#{camelize(key.to_s)}.member"
            value.each_with_index do |item, index|
              if item.is_a?(String)
                result["#{prefix}.#{index+1}"] = item
              else
                convert_ruby_to_aws(item).each do |nested_key, nested_value|
                  result["#{prefix}.#{index+1}.#{nested_key}"] = nested_value
                end
              end
            end
          when Hash
            prefix = "#{camelize(key.to_s)}"
            convert_ruby_to_aws(value).each do |nested_key, nested_value|
              result["#{prefix}.#{nested_key}"] = nested_value
            end
          else
            result[camelize(key.to_s)] = value
        end
      end
      result
    end

    # With the advent of v4 signing, we can skip the complex translation from v2
    # and ship the JSON over with nearly the same structure.
    def self.convert_ruby_to_aws_v4(value, camelizeKey)
      case value
        when Array
          return value.map{|v| convert_ruby_to_aws_v4(v, camelizeKey)}
        when Hash
          result = {}
          value.each do |k,v|
            if k != :configurations
              key = camelizeKey ? camelize(k.to_s) : k.to_s
              result[key] = convert_ruby_to_aws_v4(v, camelizeKey)
            else
              # For configuration options we want to keep property keys uncamelized.
              result[camelize(k.to_s)] = convert_ruby_to_aws_v4(v, false)
            end
          end
          return result
        else
          return value
      end
    end

    # (Used from Rails' ActiveSupport)
    def self.camelize(word)
      word.to_s.gsub(/\/(.?)/) { "::" + $1.upcase }.gsub(/(^|_)(.)/) { $2.upcase }
    end

    # AWS error responses all follow the same form.  Extract the message from
    # the error document.
    def self.parse_error_response(error_xml)
      xml_doc = Nokogiri::XML(error_xml)
      xml_doc.remove_namespaces!
      xml_doc.xpath("/ErrorResponse/Error/Message").text
    end

  end

end
