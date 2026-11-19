# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/has_http_client'

class OrderByTWAPCommand
  include HasHTTPClient

  def run(options)
    interval = options.interval
    raise Thor::MalformattedArgumentError, 'Invalid interval: --interval must be non-negative.' if interval.negative?

    number = whole_order_count(options.number_of_times)
    side = normalize_side(options.type)
    deadline = monotonic_time
    number.times do |index|
      deadline = wait_for_submission(deadline, interval) if index.positive?
      order(side, options.amount)
      deadline += interval
    end
  end

  private

  def normalize_side(type)
    side = type.to_s.upcase
    raise Thor::Error, 'Order type must be buy or sell' unless %w[BUY SELL].include?(side)

    side
  end

  def whole_order_count(number)
    count = number.to_i
    raise Thor::MalformattedArgumentError, '--number-of-times must be a whole number' unless number == count

    count
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def wait_for_submission(deadline, interval)
    now = monotonic_time
    deadline = now + interval if deadline < now
    remaining = deadline - now
    sleep remaining if remaining.positive?
    deadline
  end

  def order(side, amount) # rubocop:disable Metrics/MethodLength
    response = http_private_client.send_child_order(
      product_code: 'FX_BTC_JPY',
      child_order_type: 'MARKET',
      side: side,
      size: amount
    )

    if response['child_order_acceptance_id'].nil?
      puts "An error has occurred\n#{response}"
    else
      puts response
    end
  end
end
