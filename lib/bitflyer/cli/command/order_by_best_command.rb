# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/has_http_client'

class OrderByBestCommand
  include HasHTTPClient

  def run(options) # rubocop:disable Metrics/MethodLength
    amount = options.amount
    type = options.type
    side = normalize_side(type)

    price = fetch_ticker_price(side == 'BUY' ? 'best_bid' : 'best_ask')

    response = http_private_client.send_child_order(
      product_code: 'FX_BTC_JPY',
      child_order_type: 'LIMIT',
      side: side,
      price: price,
      size: amount
    )

    if response['child_order_acceptance_id'].nil?
      puts "An error has occurred#{response}"
    else
      puts "An order is created #{type} / #{price} / #{amount}"
    end
  end

  private

  def normalize_side(type)
    side = type.to_s.upcase
    raise Thor::Error, 'Order type must be buy or sell' unless %w[BUY SELL].include?(side)

    side
  end
end
