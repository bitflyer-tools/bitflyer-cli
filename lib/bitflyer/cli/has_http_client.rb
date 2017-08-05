require 'bitflyer'
require 'bitflyer/cli/authorization'

module HasHTTPClient
  include Authorization

  def http_public_client
    @http_public_client ||= Bitflyer.http_public_client
  end

  def http_private_client
    @http_private_client ||= Bitflyer.http_private_client(api_key, api_secret)
  end
end