# frozen_string_literal: true

require 'bitflyer/cli/authorization'
require 'bitflyer/cli/cancellation_client'

class CancelOrderCommand
  include Authorization

  class Failed < StandardError; end

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
    client = CancellationClient.new(api_key, api_secret)
    client.post("/v1/me/cancel#{type}order", 'product_code' => 'FX_BTC_JPY', "#{type}_order_id" => id)
  end

  def failure_message(response)
    body = parse_body(response.body)
    message = api_error(body)
    return message if message
    return "Cancellation request rejected (HTTP #{response.code})." unless response.code == '200'

    'Could not verify cancellation acceptance from bitFlyer.'
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

    "Cancellation request rejected (status #{response['status']})." if response['status'].to_i.negative?
  end
end
