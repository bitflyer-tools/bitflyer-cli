# frozen_string_literal: true

require 'bitflyer'
require 'bitflyer/cli/authorization'
require 'bitflyer/cli/model/position'
require 'bitflyer/cli/order_rejected'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/terminal_text'

module HasHTTPClient
  include Authorization

  class AccountLookupFailed < StandardError; end
  class PositionLookupFailed < AccountLookupFailed; end
  class TickerError < StandardError; end

  def http_public_client
    @http_public_client ||= Bitflyer.http_public_client
  end

  def http_private_client
    @http_private_client ||= Bitflyer.http_private_client(*private_credentials)
  end

  private

  def persistent_http_client
    @persistent_http_client ||= Bitflyer::Cli::PersistentHTTPClient.new(*private_credentials)
  end

  def close_persistent_http_client
    @persistent_http_client&.close
  end

  def submit_single_order(acceptance_key)
    response = yield persistent_http_client
    classification = Bitflyer::Cli::OrderRejected.classify(response, acceptance_key)
    handle_submission_classification(classification, response)
  rescue Timeout::Error, SocketError, SystemCallError, IOError,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError => e
    raise Bitflyer::Cli::OrderRejected::Unverified, "Could not verify order acceptance: #{e.message}"
  ensure
    close_persistent_http_client
  end

  def handle_submission_classification(classification, response)
    case classification
    when :rejected
      Bitflyer::Cli::OrderRejected.raise_rejection!(response.body)
    when :unverified
      raise Bitflyer::Cli::OrderRejected::Unverified, unverified_submission_message(response.status)
    end
  end

  def unverified_submission_message(status)
    return 'Could not verify order acceptance.' if status.between?(200, 299)

    "Could not verify order acceptance (HTTP #{status})."
  end

  def fetch_ticker_price(field, client:)
    price = fetch_ticker(client)[field]
    return price if (price.is_a?(Integer) || price.is_a?(Float)) && price.finite? && price.positive?

    raise TickerError, "Ticker error: #{field} must be a positive, finite number"
  end

  def fetch_ticker(client)
    ticker = client.ticker(product_code: 'FX_BTC_JPY')
    raise TickerError, 'Ticker error: unexpected response' unless ticker.is_a?(Hash)
    return ticker unless ticker.fetch('status', 0) != 0 || ticker['error_message']

    raise TickerError, "Ticker error: #{ticker_error_detail(ticker)}"
  rescue *Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS => e
    raise TickerError, "Ticker error: #{e.message}"
  end

  def ticker_error_detail(ticker)
    message = ticker['error_message']
    return ticker.inspect unless message

    Bitflyer::Cli::TerminalText.escape(message.to_s)
  end

  def position_order_size(position)
    size = position.size.abs.to_f
    return size if size.finite? && size.positive?

    warn 'Cannot submit order: position size must be positive and finite'
    nil
  end

  def fetch_collateral
    response = http_private_client.collateral
    if response.is_a?(Hash)
      status = response['status']
      collateral = response['collateral']
      rejected = status.is_a?(Numeric) && status.negative?
      return collateral.to_i if !rejected && collateral.is_a?(Numeric) && collateral.finite?
    end

    raise AccountLookupFailed, "Failed to look up collateral: #{response.inspect}"
  end

  def fetch_position
    positions = http_private_client.positions
    return Position.new(positions) if positions.is_a?(Array)

    raise PositionLookupFailed, "Failed to look up positions: #{positions.inspect}"
  rescue Position::InvalidRowError => e
    raise PositionLookupFailed, "Failed to look up positions: #{e.message}"
  rescue *Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS => e
    detail = e.api_error if e.respond_to?(:api_error)
    raise PositionLookupFailed, "Failed to look up positions: #{detail || e.message}"
  end
end
