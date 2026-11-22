# frozen_string_literal: true

require 'thor'
require 'net/http'
require 'openssl'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_amount'
require 'bitflyer/cli/order_rejected'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/twap_preview'

class OrderByTWAPCommand
  include HasHTTPClient

  alias http_private_client persistent_http_client

  def run(options)
    amount = OrderAmount.validate!(options.amount)
    interval = options.interval
    validate_interval!(interval)

    number = whole_order_count(options.number_of_times)
    side = normalize_side(options.type)
    return Bitflyer::Cli::TWAPPreview.print(side, amount, number, interval) if options[:dry_run]

    submit_slices(side, amount, number, interval)
  ensure
    close_persistent_http_client
  end

  private

  def normalize_side(type)
    side = type.to_s.upcase
    raise Thor::Error, 'Order type must be buy or sell' unless %w[BUY SELL].include?(side)

    side
  end

  def submit_slices(side, amount, number, interval)
    counts = { accepted: 0, rejected: 0, unverified: 0, unattempted: number }
    submit_on_schedule(number, interval) do
      result = order(side, amount)
      counts[result] += 1
      counts[:unattempted] -= 1
      break if result == :unverified
    end
    puts "TWAP exchange acceptance (slices): #{counts.map { |status, count| "#{count} #{status}" }.join(', ')}."
    counts
  end

  def validate_interval!(interval)
    # Keep waits representable with signed 32-bit seconds.
    raise Thor::MalformattedArgumentError, '--interval must be 0..2147483647' unless interval.between?(0, (2**31) - 1)
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
    return count if number == count && count.positive?

    raise Thor::MalformattedArgumentError, '--number-of-times must be a positive whole number'
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

  def order(side, amount)
    response = submit_order(side, amount)
  rescue Timeout::Error, SocketError, SystemCallError, IOError,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    :unverified
  else
    report_order(response)
  end

  def submit_order(side, amount)
    http_private_client.send_child_order(
      product_code: 'FX_BTC_JPY',
      child_order_type: 'MARKET',
      side: side,
      size: amount
    )
  end

  def report_order(response)
    body = response.body
    return :unverified unless body.is_a?(Hash) && verifiable_status?(response.status)

    acceptance_id = body['child_order_acceptance_id']
    if Bitflyer::Cli::OrderRejected.accepted?(response.status, acceptance_id, body)
      puts body
      return :accepted
    end
    return :unverified unless acceptance_id.nil? && Bitflyer::Cli::OrderRejected.negative_status?(body)

    puts "An error has occurred\n#{body}"
    :rejected
  end

  def verifiable_status?(status)
    status.between?(200, 299) || (status.between?(400, 499) && status != 408)
  end
end
