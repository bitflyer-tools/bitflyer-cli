# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'
require 'bitflyer/cli/terminal_text'

class CancellationClient
  API_URL = 'https://api.bitflyer.jp'

  Result = Data.define(:outcome, :http_code, :exchange_status, :message) do
    def unverified_http_status?
      http_code == '408' || http_code.to_i.between?(500, 599)
    end
  end

  def initialize(key, secret)
    @key = key
    @secret = secret
  end

  def post(path, params)
    classify(send_request(path, params))
  rescue Timeout::Error, SocketError, SystemCallError, IOError,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    Result.new(:unverified, nil, nil, nil)
  end

  private

  def send_request(path, params)
    uri = URI.join(API_URL, path)
    request = Net::HTTP::Post.new(uri, 'Accept' => 'application/json', 'Content-Type' => 'application/json')
    request.body = JSON.generate(params)
    sign(request) if @key && @secret
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  end

  def classify(response)
    code = response.code
    body = response.body.to_s
    return Result.new(:accepted, code, nil, nil) if code == '200' && body.empty?

    unverified = Result.new(:unverified, code, nil, nil)
    return unverified if unverified.unverified_http_status?

    error = parse_error(body)
    status = error['status']
    return unverified unless status.is_a?(Integer) && status.negative?

    Result.new(:rejected, code, status, Bitflyer::Cli::TerminalText.escape(error['error_message'].to_s))
  end

  def parse_error(body)
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def sign(request)
    timestamp = Time.now.to_i.to_s
    request['ACCESS-KEY'] = @key
    request['ACCESS-TIMESTAMP'] = timestamp
    request['ACCESS-SIGN'] = OpenSSL::HMAC.hexdigest(
      'SHA256', @secret, timestamp + request.method + request.path + request.body
    )
  end
end
