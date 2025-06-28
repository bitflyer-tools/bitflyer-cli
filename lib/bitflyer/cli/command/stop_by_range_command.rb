# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/model/position'

class StopByRangeCommand
  include HasHTTPClient

  def run(options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    position = Position.new(http_private_client.positions)
    return puts "You don't have any position now." if position.empty?

    side = position.average.positive? ? 'SELL' : 'BUY'
    price = position.average.abs + (options.range * (side == 'BUY' ? 1.0 : -1.0))

    response = http_private_client.send_parent_order(
      order_method: 'SIMPLE',
      parameters: [{
        product_code: 'FX_BTC_JPY',
        condition_type: 'STOP',
        side: side,
        trigger_price: price,
        size: position.size.to_f
      }]
    )

    if response['parent_order_acceptance_id'].nil?
      puts "An error has occurred#{response}"
    else
      puts "Set limit order #{side} / #{price} / #{position.size.to_f}"
    end
  end
end
