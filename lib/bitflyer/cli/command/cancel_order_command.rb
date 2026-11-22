# frozen_string_literal: true

require 'bitflyer/cli/authorization'
require 'bitflyer/cli/cancellation_client'

class CancelOrderCommand
  include Authorization

  class Failed < StandardError; end

  UNVERIFIED = 'Could not verify cancellation acceptance from bitFlyer.'

  def run(type, id, confirm_parent: false)
    validate_order(type, id, confirm_parent)
    response = cancel(type, id)
    raise Failed, failure_message(response) unless response.code == '200' && response.body.to_s.empty?

    puts "Cancellation request accepted for #{type} order #{id}."
  end

  private

  def validate_order(type, id, confirm_parent)
    raise Failed, 'Order type must be child or parent.' unless %w[child parent].include?(type)
    raise Failed, 'Order ID is required.' if id.to_s.strip.empty?
    return unless type == 'parent' && !confirm_parent

    raise Failed, 'Canceling a parent strategy also cancels its associated orders. Use --confirm-parent to proceed.'
  end

  def cancel(type, id)
    client = CancellationClient.new(*private_credentials)
    client.post("/v1/me/cancel#{type}order", 'product_code' => 'FX_BTC_JPY', "#{type}_order_id" => id)
  rescue Timeout::Error, SocketError, SystemCallError, IOError,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    raise Failed, UNVERIFIED
  end

  def failure_message(response)
    if response.code.to_i.between?(500, 599)
      return "Could not verify cancellation acceptance from bitFlyer (HTTP #{response.code})."
    end

    api_error(parse_body(response.body)) || UNVERIFIED
  end

  def parse_body(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    nil
  end

  def api_error(response)
    return unless response.is_a?(Hash)

    message = response['error_message'].to_s
    return "Cancellation request rejected. #{message}" unless message.empty?

    status = response['status']
    return unless status.is_a?(Integer) && status.negative?

    "Cancellation request rejected (status #{status})."
  end
end
