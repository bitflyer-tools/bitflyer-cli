# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'uri'

class CancellationClient
  API_URL = 'https://api.bitflyer.jp'

  def initialize(key, secret)
    @key = key
    @secret = secret
  end

  def post(path, params)
    uri = URI.join(API_URL, path)
    request = Net::HTTP::Post.new(uri, 'Accept' => 'application/json', 'Content-Type' => 'application/json')
    request.body = JSON.generate(params)
    sign(request) if @key && @secret
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
  end

  private

  def sign(request)
    timestamp = Time.now.to_i.to_s
    request['ACCESS-KEY'] = @key
    request['ACCESS-TIMESTAMP'] = timestamp
    request['ACCESS-SIGN'] = OpenSSL::HMAC.hexdigest(
      'SHA256', @secret, timestamp + request.method + request.path + request.body
    )
  end
end
