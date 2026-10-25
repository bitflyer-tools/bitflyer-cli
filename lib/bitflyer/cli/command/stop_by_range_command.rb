# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/model/position'

class StopByRangeCommand
  include HasHTTPClient

  def run(options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    position = Position.new(http_private_client.positions)
    return puts "You don't have any position now." if position.empty?

    side = position.size.positive? ? 'SELL' : 'BUY'
    size = position.size.abs.to_f
    price = position.average.abs + (options.range * (side == 'BUY' ? 1.0 : -1.0))

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

    if response['parent_order_acceptance_id'].nil?
      puts "An error has occurred#{response}"
    else
      puts "Set stop order #{side} / #{price} / #{size}"
    end
  end
end
