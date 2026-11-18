# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/has_http_client'

class OrderByTWAPCommand
  include HasHTTPClient

  def run(options)
    number = options.number_of_times
    interval = options.interval
    validate_schedule(number, interval)

    counts = { accepted: 0, rejected: 0 }
    number.to_i.times do |index|
      sleep interval if index.positive?
      counts[order(options.type, options.amount)] += 1
    end
    puts "TWAP exchange acceptance (slices): #{counts[:accepted]} accepted, #{counts[:rejected]} rejected."
    counts
  end

  private

  def validate_schedule(number, interval)
    raise Thor::MalformattedArgumentError, 'Invalid interval: --interval must be non-negative.' if interval.negative?

    raise Thor::MalformattedArgumentError, '--number-of-times must be a whole number' unless number == number.to_i
  end

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
