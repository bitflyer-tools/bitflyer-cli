# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'

class CounterTradeCommand
  include HasHTTPClient

  def run # rubocop:disable Metrics/MethodLength
    position = Position.new(http_private_client.positions)
    size = position.size.abs.to_f
    type = position.size.positive? ? 'SELL' : 'BUY'
    response = http_private_client.send_child_order(
      product_code: 'FX_BTC_JPY',
      child_order_type: 'MARKET',
      side: type,
      size: size
    )
    if response['child_order_acceptance_id'].nil?
      puts "An error has occurred#{response}"
    else
      puts "Clear position #{type} / #{size}"
    end
  end
end
