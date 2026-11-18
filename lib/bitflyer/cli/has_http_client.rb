# frozen_string_literal: true

require 'bitflyer'
require 'bitflyer/cli/authorization'
require 'bitflyer/cli/model/position'

module HasHTTPClient
  include Authorization

  def http_public_client
    @http_public_client ||= Bitflyer.http_public_client
  end

  def http_private_client
    @http_private_client ||= Bitflyer.http_private_client(api_key, api_secret)
  end

  private

  def fetch_position
    positions = http_private_client.positions
    return Position.new(positions) if positions.is_a?(Array)

    warn "Failed to look up positions: #{positions.inspect}"
    nil
  end
end
