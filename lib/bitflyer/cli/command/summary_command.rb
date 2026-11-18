# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/has_realtime_client'
require 'bitflyer/cli/ext/string'
require 'bitflyer/cli/model/position'

class SummaryCommand
  include HasHTTPClient
  include HasRealtimeClient

  def initialize
    @current_price = 0.0

    realtime_client.executions_fx_btc_jpy = lambda { |message|
      message.each { |m| @current_price = m['price'].to_f }
    }

    update_balance
  end

  def run
    $stdout.sync = true
    print "\e[?25l"
    Thread.new { poll_account }
    puts "\n" * 3
    render_loop
  rescue Interrupt
    # exit
  ensure
    print "\e[?25h"
  end

  private

  def render_loop
    loop do
      print frame
      sleep 0.1
    end
  end

  def poll_account
    loop do
      sleep 5
      update_balance
    rescue IOError, Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      position, balance = @account_snapshot
      @account_snapshot = [position, balance, true].freeze
    end
  end

  def update_balance
    position = Position.new(http_private_client.positions)
    balance = http_private_client.collateral['collateral'].to_i
    @account_snapshot = [position, balance, false].freeze
  end

  def frame
    position, balance, stale = @account_snapshot
    price = @current_price
    average = position.average
    spread = spread(price, average)

    <<~EOS
      \e[4F\e[0JCurrent:  #{price.to_i.to_s.split_by_comma}
      Position: #{average.to_s.split_by_comma} * #{position.size.to_f}
      Spread:   #{spread.to_s.split_by_comma.color_with_number(spread)}
      Balance:  #{format_balance(balance, profit(position, price), stale)}
    EOS
  end

  def format_balance(balance, profit, stale)
    total = (balance + profit).to_s.split_by_comma.ljust(15, ' ')
    "#{total} (#{profit.to_s.split_by_comma.color_with_number(profit)})#{' [stale]' if stale}"
  end

  def profit(position, price)
    return 0 if price.zero?

    position.profit(price).to_i
  end

  def spread(price, average)
    return 0 if price.zero? || average.zero?

    price.to_i - average
  end
end
