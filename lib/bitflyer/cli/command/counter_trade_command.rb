# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_rejected'

class CounterTradeCommand
  include HasHTTPClient

  def run # rubocop:disable Metrics/MethodLength
    position = fetch_position
    return unless position
    return puts "You don't have any position now." if position.empty?

    size = position.size.abs.to_f
    type = position.size.positive? ? 'SELL' : 'BUY'
    response = http_private_client.send_child_order(
      product_code: 'FX_BTC_JPY',
      child_order_type: 'MARKET',
      side: type,
      size: size
    )
    Bitflyer::Cli::OrderRejected.check!(response, 'child_order_acceptance_id')
    puts "Clear position #{type} / #{size}"
  end
end
