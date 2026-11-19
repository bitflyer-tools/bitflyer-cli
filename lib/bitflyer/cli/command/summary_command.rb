# frozen_string_literal: true

require 'colorize'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/has_realtime_client'
require 'bitflyer/cli/model/position'

class SummaryCommand
  include HasHTTPClient
  include HasRealtimeClient

  PRICE_FRESHNESS_LIMIT = 30 # seconds

  def initialize
    @execution = nil
    realtime_client.disconnected = ->(_error) { @execution = nil }
    realtime_client.executions_fx_btc_jpy = lambda { |message|
      execution = message.last
      @execution = [execution['price'].to_f, monotonic_time] if execution
    }

    update_balance
  end

  def run
    return unless @account_snapshot

    $stdout.sync = true
    print "\e[?25l"
    refresh_balance
    render
  rescue Interrupt
    # exit
  ensure
    print "\e[?25h"
  end

  private

  def render
    puts "\n" * 3
    previous_frame = nil

    loop do
      current_frame = frame
      if current_frame != previous_frame
        print current_frame
        previous_frame = current_frame
      end
      sleep 0.1
    end
  end

  def refresh_balance
    Thread.new do
      loop do
        sleep 5
        update_balance
      end
    end
  end

  def update_balance
    position = fetch_position
    return unless position

    balance = http_private_client.collateral['collateral'].to_i
    @account_snapshot = [position, balance].freeze
  end

  def frame
    position, balance = @account_snapshot
    price = fresh_price
    average = position.average
    <<~EOS
      \e[4F\e[0JCurrent:  #{price ? group_digits(price.to_i) : 'Stale'}
      Position: #{group_digits(average)} * #{position.size.to_f}
      #{price ? marked_values(price, position, balance, average) : "Spread:   N/A\nBalance:  N/A (N/A)"}
    EOS
  end

  def marked_values(price, position, balance, average)
    profit = position.profit(price).to_i
    spread = position.flat? ? 0 : price.to_i - average
    <<~EOS.chomp
      Spread:   #{colored_amount(spread)}
      Balance:  #{group_digits(balance + profit).ljust(15, ' ')} (#{colored_amount(profit)})
    EOS
  end

  def colored_amount(amount)
    formatted = group_digits(amount)
    amount >= 0 ? "+#{formatted.colorize(:green)}" : formatted.colorize(:red)
  end

  def group_digits(amount)
    amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  end

  def fresh_price
    price, received_at = @execution
    price if received_at && monotonic_time - received_at < PRICE_FRESHNESS_LIMIT
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
