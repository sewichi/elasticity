module Elasticity

  class MissingKeyError < StandardError;
  end

  class AwsRequest

    SERVICE_NAME = 'elasticmapreduce'

    attr_reader :access_key
    attr_reader :secret_key
    attr_reader :host
    attr_reader :protocol

    # Supported values for options:
    #  :region - AWS region (e.g. us-west-1)
    #  :secure - true or false, default true.
    def initialize(access=nil, secret=nil, options={})
      @access_key = get_access_key(access)
      @secret_key = get_secret_key(secret)
      @region = {:region => 'us-east-1'}.merge(options)[:region]
      @host = "elasticmapreduce.#@region.amazonaws.com"
      @protocol = {:secure => true}.merge(options)[:secure] ? 'https' : 'http'
      @timestamp = Time.now.utc
    end

    def headers
      headers = {
        'Authorization' => "AWS4-HMAC-SHA256 Credential=#{@access_key}/#{credential_scope}, SignedHeaders=content-type;host;user-agent;x-amz-content-sha256;x-amz-date;x-amz-target, Signature=#{aws_v4_signature}",
        'Content-Type' => 'application/x-amz-json-1.1',
        'Host' => host,
        'User-Agent' => "elasticity/#{Elasticity::VERSION}",
        'X-Amz-Content-SHA256' => Digest::SHA256.hexdigest(payload),
        'X-Amz-Date' => @timestamp.strftime('%Y%m%dT%H%M%SZ'),
        'X-Amz-Target' => "ElasticMapReduce.#{@operation}",
      }
      headers
    end

    def url
      "https://#{host}"
    end

    def payload
      ruby_params = AwsRequest.convert_ruby_to_aws_v4(@ruby_service_hash, true)
      ruby_params.to_json
    end

    def host
      "elasticmapreduce.#{@region}.amazonaws.com"
    end

    def credential_scope
      "#{@timestamp.strftime('%Y%m%d')}/#{@region}/#{SERVICE_NAME}/aws4_request"
    end

    # Task 1: Create a Canonical Request For Signature Version 4
    #   http://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
    def canonical_request
      [
        'POST',
        '/',
        '',
        'content-type:application/x-amz-json-1.1',
        "host:#{host}",
        "user-agent:elasticity/#{Elasticity::VERSION}",
        "x-amz-content-sha256:#{Digest::SHA256.hexdigest(payload)}",
        "x-amz-date:#{@timestamp.strftime('%Y%m%dT%H%M%SZ')}",
        "x-amz-target:ElasticMapReduce.#{@operation}",
        '',
        'content-type;host;user-agent;x-amz-content-sha256;x-amz-date;x-amz-target',
        Digest::SHA256.hexdigest(payload)
      ].join("\n")
    end

    # Task 2: Create a String to Sign for Signature Version 4
    #   http://docs.aws.amazon.com/general/latest/gr/sigv4-create-string-to-sign.html
    def string_to_sign
      [
        'AWS4-HMAC-SHA256',
        @timestamp.strftime('%Y%m%dT%H%M%SZ'),
        credential_scope,
        Digest::SHA256.hexdigest(canonical_request)
      ].join("\n")
    end

    # Task 3: Calculate the AWS Signature Version 4
    #   http://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
    def aws_v4_signature
      date = OpenSSL::HMAC.digest('sha256', 'AWS4' + @secret_key, @timestamp.strftime('%Y%m%d'))
      region = OpenSSL::HMAC.digest('sha256', date, @region)
      service = OpenSSL::HMAC.digest('sha256', region, SERVICE_NAME)
      signing_key = OpenSSL::HMAC.digest('sha256', service, 'aws4_request')

      OpenSSL::HMAC.hexdigest('sha256', signing_key, string_to_sign)
    end

    def submit(ruby_params)
      if ruby_params.key?(:release_label)
        @ruby_service_hash = ruby_params
        @operation = ruby_params[:operation]
      else
        aws_params = AwsRequest.convert_ruby_to_aws(ruby_params)
        signed_params = sign_params(aws_params)
      end

      begin
        if ruby_params.key?(:release_label)
          RestClient.post("#@protocol://#@host", payload, headers)
        else
          RestClient.post("#@protocol://#@host", signed_params, :content_type => 'application/x-www-form-urlencoded; charset=utf-8')
        end
      rescue RestClient::BadRequest => e
        raise ArgumentError, AwsRequest.parse_error_response(e.http_body)
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

    # (Used from RightScale's right_aws gem.)
    # EC2, SQS, SDB and EMR requests must be signed by this guy.
    # See: http://docs.amazonwebservices.com/AmazonSimpleDB/2007-11-07/DeveloperGuide/index.html?REST_RESTAuth.html
    #      http://developer.amazonwebservices.com/connect/entry.jspa?externalID=1928
    def sign_params(service_hash)
      service_hash.merge!({
        'AWSAccessKeyId' => @access_key,
        'Timestamp' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.000Z'),
        'SignatureVersion' => '2',
        'SignatureMethod' => 'HmacSHA256'
      })
      canonical_string = service_hash.keys.sort.map do |key|
        "#{AwsRequest.aws_escape(key)}=#{AwsRequest.aws_escape(service_hash[key])}"
      end.join('&')
      string_to_sign = "POST\n#{@host.downcase}\n/\n#{canonical_string}"
      signature = AwsRequest.aws_escape(Base64.encode64(OpenSSL::HMAC.digest("sha256", @secret_key, string_to_sign)).strip)
      "#{canonical_string}&Signature=#{signature}"
    end

    # (Used from RightScale's right_aws gem)
    # Escape a string according to Amazon's rules.
    # See: http://docs.amazonwebservices.com/AmazonSimpleDB/2007-11-07/DeveloperGuide/index.html?REST_RESTAuth.html
    def self.aws_escape(param)
      ERB::Util.url_encode(param)
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
