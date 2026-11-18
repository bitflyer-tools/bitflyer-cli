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

  def run # rubocop:disable Metrics/MethodLength
    $stdout.sync = true
    print "\e[?25l"

    Thread.new do
      loop do
        sleep 5
        update_balance
      end
    end

    puts "\n" * 3

    loop do
      print frame
      sleep 0.1
    end
  rescue Interrupt
    # exit
  ensure
    print "\e[?25h"
  end

  private

  def update_balance
    position = Position.new(http_private_client.positions)
    balance = http_private_client.collateral['collateral'].to_i
    @account_snapshot = [position, balance].freeze
  end

  def frame # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    position, balance = @account_snapshot
    price = @current_price
    average = position.average
    profit = price.zero? ? 0 : position.profit(price).to_i
    spread = price.zero? || average.zero? ? 0 : price.to_i - average
    total = (balance + profit).to_s.split_by_comma.ljust(15)

    <<~EOS
      \e[4F\e[0JCurrent:  #{price.to_i.to_s.split_by_comma}
      Position: #{average.to_s.split_by_comma} * #{position.size.to_f}
      Spread:   #{spread.to_s.split_by_comma.color_with_number(spread)}
      Balance:  #{total} (#{profit.to_s.split_by_comma.color_with_number(profit)})
    EOS
  end
end
