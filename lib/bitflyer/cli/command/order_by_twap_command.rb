# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'

class OrderByTWAPCommand
  include HasHTTPClient

  def run(options)
    counts = { accepted: 0, rejected: 0 }
    options.number_of_times.to_i.times do
      counts[order(options.type, options.amount)] += 1
      sleep options.interval
    end
    puts "TWAP exchange acceptance (slices): #{counts[:accepted]} accepted, #{counts[:rejected]} rejected."
    counts
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
      :rejected
    else
      puts response
      :accepted
    end
  end
end
