# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_rejected'

class StopByRangeCommand
  include HasHTTPClient

  def run(options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    raise ArgumentError, 'Range must be positive' unless options.range.positive?

    position = fetch_position
    return unless position

    return puts "You don't have any position now." if position.flat?

    side = position.size.positive? ? 'SELL' : 'BUY'
    size = position.size.abs.to_f
    price = position.average + (options.range * (side == 'BUY' ? 1.0 : -1.0))

    response = http_private_client.send_parent_order(
      order_method: 'SIMPLE',
      parameters: [{
        product_code: 'FX_BTC_JPY',
        condition_type: 'STOP',
        side: side,
        trigger_price: price,
        size: size
      }]
    )

    Bitflyer::Cli::OrderRejected.check!(response, 'parent_order_acceptance_id')
    puts "Set stop order #{side} / #{price} / #{size}"
  end
end
