require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/has_realtime_client'
require 'bitflyer/cli/ext/string'
require 'bitflyer/cli/model/position'

class SummaryCommand
  include HasHTTPClient
  include HasRealtimeClient

  BUFFER_SIZE = 30.freeze

  def initialize
    @current_price = 0.0

    realtime_client.executions_fx_btc_jpy = ->(message) {
      message.each { |m| @current_price = m['price'].to_f }
    }

    update_balance
  end

  def run
    $stdout.sync = true

    Thread.new do
      while true
        update_balance
        sleep 5
      end
    end

    while true
      print "\e[3F\e[0J"
      print "Current:  " + @current_price.to_i.to_s.split_by_comma
      print "\nPosition: " + "#{@position.average} * #{@position.size.to_f}".to_s.split_by_comma
      print "\nSpread:   " + spread.to_s.split_by_comma.color_with_number(spread)
      print "\nBalance:  " + (@balance + profit).to_s.split_by_comma.ljust(15, ' ') + "(#{profit.to_s.split_by_comma.color_with_number(profit)})"
      sleep 0.1
    end
  end

  private

  def update_balance
    @position = Position.new(http_private_client.positions)
    @balance = http_private_client.collateral['collateral'].to_i
  end

  def profit
    return 0 if @current_price == 0
    @position.profit(@current_price).to_i
  end

  def spread
    return 0 if @current_price == 0
    return 0 if @position.average.to_i == 0
    @current_price.to_i - @position.average.to_i
  end
end