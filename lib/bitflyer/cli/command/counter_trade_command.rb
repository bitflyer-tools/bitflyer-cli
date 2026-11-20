# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_rejected'

class CounterTradeCommand
  include HasHTTPClient

  def run
    position = fetch_position
    return unless position
    return puts "You don't have any position now." if position.empty?
    return puts 'Your net position is already flat.' if position.flat?

    size = position_order_size(position)
    return unless size

    type = position.size.positive? ? 'SELL' : 'BUY'
    submit_order(type, size)
  end

  private

  def submit_order(type, size)
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
