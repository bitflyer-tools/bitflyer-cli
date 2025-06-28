# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/has_realtime_client'
require 'bitflyer/cli/ext/string'
require 'bitflyer/cli/model/position'

class SummaryCommand
  include HasHTTPClient
  include HasRealtimeClient

  BUFFER_SIZE = 30

  def initialize
    @current_price = 0.0

    realtime_client.executions_fx_btc_jpy = lambda { |message|
      message.each { |m| @current_price = m['price'].to_f }
    }

    update_balance
  end

  def run # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    $stdout.sync = true

    Thread.new do
      loop do
        update_balance
        sleep 5
      end
    end

    loop do
      print <<~EOS
        \e[4F\e[0JCurrent:  #{@current_price.to_i.to_s.split_by_comma}
        Position: #{@position.average.to_s.split_by_comma} * #{@position.size.to_f}
        Spread:   #{spread.to_s.split_by_comma.color_with_number(spread)}
        Balance:  #{(@balance + profit).to_s.split_by_comma.ljust(15, ' ')} (#{profit.to_s.split_by_comma.color_with_number(profit)})
      EOS
      sleep 0.1
    end
  end

  private

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
