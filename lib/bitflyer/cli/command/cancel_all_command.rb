# frozen_string_literal: true

require 'bitflyer/cli/authorization'
require 'bitflyer/cli/cancellation_client'

class CancelAllCommand
  include Authorization

  class Rejected < StandardError; end

  UNVERIFIED = 'Could not verify cancel-all acceptance from bitFlyer'

  def run
    response = cancel
    return if response.code == '200' && response.body.to_s.empty?

    raise Rejected, failure_message(response)
  end

  private

  def failure_message(response)
    unverified = "#{UNVERIFIED} (HTTP #{response.code})."
    return unverified if response.code.to_i.between?(500, 599)

    api_error(response.body) || unverified
  end

  def cancel
    CancellationClient.new(*private_credentials).post('/v1/me/cancelallchildorders', product_code: 'FX_BTC_JPY')
  rescue Timeout::Error, SocketError, SystemCallError, IOError,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    raise Rejected, "#{UNVERIFIED}."
  end

  def api_error(body)
    response = JSON.parse(body.to_s)
    return unless response.is_a?(Hash)

    status = response['status']
    return unless status.is_a?(Integer) && status.negative?

    message = response['error_message'].to_s
    message.empty? ? "Cancel-all request rejected (status #{status})" : message
  rescue JSON::ParserError
    nil
  end
end
