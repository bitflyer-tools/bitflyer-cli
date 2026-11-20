# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'

class StopByRangeCommand
  include HasHTTPClient

  def run(options)
    raise ArgumentError, 'Range must be positive' unless options.range.positive?

    position = fetch_position
    return unless position

    return puts "You don't have any position now." if position.flat?

    size = position_order_size(position)
    return unless size

    side = position.size.positive? ? 'SELL' : 'BUY'
    price = position.average + (options.range * (side == 'BUY' ? 1.0 : -1.0))

    submit_stop_order(side, price, size)
  end

  private

  def submit_stop_order(side, price, size) # rubocop:disable Metrics/MethodLength
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
