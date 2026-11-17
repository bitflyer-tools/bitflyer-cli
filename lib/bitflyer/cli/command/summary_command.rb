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
        update_balance
        sleep 5
      end
    end

    puts "\n" * 3
    previous_frame = nil

    loop do
      frame = summary_frame
      if frame != previous_frame
        print frame
        previous_frame = frame
      end
      sleep 0.1
    end
  rescue Interrupt
    # exit
  ensure
    print "\e[?25h"
  end

  private

  def summary_frame
    current_spread = spread

    <<~EOS
      \e[4F\e[0JCurrent:  #{@current_price.to_i.to_s.split_by_comma}
      Position: #{@position.average.to_s.split_by_comma} * #{@position.size.to_f}
      Spread:   #{current_spread.to_s.split_by_comma.color_with_number(current_spread)}
      Balance:  #{formatted_balance}
    EOS
  end

  def formatted_balance
    current_profit = profit
    balance = (@balance + current_profit).to_s.split_by_comma.ljust(15, ' ')
    "#{balance} (#{current_profit.to_s.split_by_comma.color_with_number(current_profit)})"
  end

  def update_balance
    @position = Position.new(http_private_client.positions)
    @balance = http_private_client.collateral['collateral'].to_i
  end

  def profit
    return 0 if @current_price.zero?

    @position.profit(@current_price).to_i
  end

  def spread
    return 0 if @current_price.zero?
    return 0 if @position.average.to_i.zero?

    @current_price.to_i - @position.average.to_i
  end
end
