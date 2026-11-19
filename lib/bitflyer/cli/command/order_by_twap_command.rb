# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/has_http_client'

class OrderByTWAPCommand
  include HasHTTPClient

  def run(options)
    interval = options.interval
    raise Thor::MalformattedArgumentError, 'Invalid interval: --interval must be non-negative.' if interval.negative?

    number = whole_order_count(options.number_of_times)
    counts = { accepted: 0, rejected: 0 }
    submit_on_schedule(number, interval) do
      counts[order(options.type, options.amount)] += 1
    end
    puts "TWAP exchange acceptance (slices): #{counts[:accepted]} accepted, #{counts[:rejected]} rejected."
    counts
  end

  private

  def submit_on_schedule(number, interval)
    deadline = monotonic_time
    number.times do |index|
      deadline = wait_for_submission(deadline, interval) if index.positive?
      yield
      deadline += interval
    end
  end

  def whole_order_count(number)
    count = number.to_i
    unless number == count && count.positive?
      raise Thor::MalformattedArgumentError, '--number-of-times must be a positive whole number'
    end

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
