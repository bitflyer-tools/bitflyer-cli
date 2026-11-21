# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_rejected'

class StopByRangeCommand
  include HasHTTPClient

  class LookupFailed < StandardError; end

  PRODUCT_CODE = 'FX_BTC_JPY'
  PAGE_SIZE = 100

  def run(options)
    raise ArgumentError, 'Range must be positive' unless options.range.positive?

    position = fetch_position

    return puts "You don't have any position now." if position.flat?

    stop = stop_parameters(position, options.range)
    return unless stop

    order_id = existing_stop_id(stop)
    description = stop.values_at(:side, :trigger_price, :size).join(' / ')
    return puts "Existing stop order #{description} (#{order_id})" if order_id

    submit_stop(stop, description)
  end

  private

  def stop_parameters(position, range)
    size = position_order_size(position)
    return unless size

    side = position.size.positive? ? 'SELL' : 'BUY'
    {
      product_code: PRODUCT_CODE,
      condition_type: 'STOP',
      side: side,
      trigger_price: position.average + (range * (side == 'BUY' ? 1.0 : -1.0)),
      size: size
    }
  end

  def existing_stop_id(stop)
    before = nil
    loop do
      orders = active_parent_orders(before)
      match = orders.find { |order| matching_stop?(order, stop) }
      return match.fetch('parent_order_id') if match
      return if orders.size < PAGE_SIZE

      before = next_cursor(orders, before)
    end
  end

  def next_cursor(orders, before)
    ids = orders.map { |order| order['id'] }
    if ids.all? { |id| id.is_a?(Integer) && id.positive? }
      cursor = ids.min
      return cursor if before.nil? || cursor < before
    end

    raise LookupFailed, 'Could not paginate active parent orders.'
  end

  def active_parent_orders(before)
    orders = http_private_client.parent_orders(
      product_code: PRODUCT_CODE, parent_order_state: 'ACTIVE', count: PAGE_SIZE, before: before
    )
    return orders if orders.is_a?(Array)

    raise LookupFailed, "Failed to look up active parent orders: #{orders.inspect}"
  end

  def matching_stop?(order, stop)
    return false unless order['parent_order_type'] == 'STOP'

    detail = parent_order_detail(order.fetch('parent_order_id'))
    parameters = detail.fetch('parameters')
    detail['order_method'] == 'SIMPLE' && parameters.one? &&
      stop.all? { |key, value| parameters.first[key.to_s] == value }
  end

  def parent_order_detail(order_id)
    detail = http_private_client.parent_order(parent_order_id: order_id)
    return detail if detail.is_a?(Hash) && detail['parameters'].is_a?(Array)

    raise LookupFailed, "Failed to look up parent order #{order_id}: #{detail.inspect}"
  end

  def submit_stop(stop, description)
    response = http_private_client.send_parent_order(order_method: 'SIMPLE', parameters: [stop])
    Bitflyer::Cli::OrderRejected.check!(response, 'parent_order_acceptance_id')
    puts "Set stop order #{description}"
  end
end
