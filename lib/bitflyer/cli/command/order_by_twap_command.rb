# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'

class OrderByTWAPCommand
  include HasHTTPClient

  def run(options)
    type = options.type
    amount = options.amount
    number = options.number_of_times
    interval = options.interval

    number.to_i.times do |_|
      order(type, amount)
      sleep interval
    end
  end

  private

  def order(type, amount) # rubocop:disable Metrics/MethodLength
    response = http_private_client.send_child_order(
      product_code: 'FX_BTC_JPY',
      child_order_type: 'MARKET',
      side: type.upcase,
      size: amount
    )

    if response['child_order_acceptance_id'].nil?
      puts "An error has occurred\n#{response}"
    else
      puts response
    end
  end
end
