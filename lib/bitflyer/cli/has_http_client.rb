# frozen_string_literal: true

require 'bitflyer'
require 'bitflyer/cli/authorization'
require 'bitflyer/cli/model/position'

module HasHTTPClient
  include Authorization

  class TickerError < StandardError; end

  def http_public_client
    @http_public_client ||= Bitflyer.http_public_client
  end

  def http_private_client
    @http_private_client ||= Bitflyer.http_private_client(api_key, api_secret)
  end

  private

  def persistent_http_client
    @persistent_http_client ||= Bitflyer::Cli::PersistentHTTPClient.new(api_key, api_secret)
  end

  def close_persistent_http_client
    @persistent_http_client&.close
  end

  def fetch_ticker_price(field)
    price = fetch_ticker[field]
    return price if (price.is_a?(Integer) || price.is_a?(Float)) && price.finite? && price.positive?

    raise TickerError, "Ticker error: #{field} must be a positive, finite number"
  end

  def fetch_ticker
    ticker = http_public_client.ticker(product_code: 'FX_BTC_JPY')
    raise TickerError, 'Ticker error: unexpected response' unless ticker.is_a?(Hash)

    if ticker.fetch('status', 0) != 0 || ticker['error_message']
      raise TickerError, "Ticker error: #{ticker['error_message'] || ticker.inspect}"
    end

    ticker
  end

  def position_order_size(position)
    size = position.size.abs.to_f
    return size if size.finite? && size.positive?

    warn 'Cannot submit order: position size must be positive and finite'
    nil
  end

  def fetch_position
    positions = http_private_client.positions
    return Position.new(positions) if positions.is_a?(Array)

    warn "Failed to look up positions: #{positions.inspect}"
    nil
  rescue Position::InvalidRowError => e
    warn "Failed to look up positions: #{e.message}"
    nil
  end
end
