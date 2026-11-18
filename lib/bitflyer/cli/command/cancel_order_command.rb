# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'

class CancelOrderCommand
  include HasHTTPClient

  class Failed < StandardError; end

  def run(type, id, confirm_parent: false)
    validate_order(type, id, confirm_parent)
    response = cancel(type, id)
    raise Failed, failure_message(response) unless response == ''

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
    if type == 'child'
      http_private_client.cancel_child_order(product_code: 'FX_BTC_JPY', child_order_id: id)
    else
      http_private_client.cancel_parent_order(product_code: 'FX_BTC_JPY', parent_order_id: id)
    end
  end

  def failure_message(response)
    return 'Could not verify cancellation acceptance from bitFlyer.' unless response.is_a?(Hash)

    message = response['error_message'].to_s
    return "Cancellation request rejected. #{message}" unless message.empty?
    return "Cancellation request rejected (status #{response['status']})." if response['status'].to_i.negative?

    'Could not verify cancellation acceptance from bitFlyer.'
  end
end
