# frozen_string_literal: true

require 'bitflyer/cli/authorization'
require 'bitflyer/cli/cancellation_client'

class CancelOrderCommand
  include Authorization

  class Failed < StandardError; end

  UNVERIFIED = 'Could not verify cancellation acceptance from bitFlyer'

  def run(type, id, confirm_parent: false)
    validate_order(type, id, confirm_parent)
    result = cancel(type, id)
    raise Failed, failure_message(result) unless result.outcome == :accepted

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
  end

  def failure_message(result)
    return "#{UNVERIFIED} (HTTP #{result.http_code})." if result.unverified_http_status?
    return "#{UNVERIFIED}." unless result.outcome == :rejected
    return "Cancellation request rejected. #{result.message}" unless result.message.empty?

    "Cancellation request rejected (status #{result.exchange_status})."
  end
end
