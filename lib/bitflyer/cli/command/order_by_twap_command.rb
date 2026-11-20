# frozen_string_literal: true

require 'thor'
require 'net/http'
require 'openssl'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/persistent_http_client'

class OrderByTWAPCommand
  include HasHTTPClient

  alias http_private_client persistent_http_client

  def run(options)
    interval = options.interval
    raise Thor::MalformattedArgumentError, 'Invalid interval: --interval must be non-negative.' if interval.negative?

    counts = submit_slices(options, whole_order_count(options.number_of_times), interval)
    puts "TWAP exchange acceptance (slices): #{counts.map { |status, count| "#{count} #{status}" }.join(', ')}."
    counts
  ensure
    close_persistent_http_client
  end

  private

  def submit_slices(options, number, interval)
    counts = { accepted: 0, rejected: 0, unverified: 0, unattempted: number }
    submit_on_schedule(number, interval) do
      result = order(options.type, options.amount)
      counts[result] += 1
      counts[:unattempted] -= 1
      break if result == :unverified
    end
    counts
  end

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

  def order(type, amount)
    response = submit_order(type, amount)
  rescue Timeout::Error, SocketError, SystemCallError, IOError,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    :unverified
  else
    report_order(response)
  end

  def submit_order(type, amount)
    http_private_client.send_child_order(
      product_code: 'FX_BTC_JPY',
      child_order_type: 'MARKET',
      side: type.upcase,
      size: amount
    )
  end

  def report_order(response)
    if response['child_order_acceptance_id'].nil?
      puts "An error has occurred\n#{response}"
      :rejected
    else
      puts response
      :accepted
    end
  end
end
