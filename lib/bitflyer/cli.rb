require 'thor'
require 'bitflyer/cli/command/cancel_all_command'
require 'bitflyer/cli/command/counter_trade_command'
require 'bitflyer/cli/command/ifdoco_by_range_command'
require 'bitflyer/cli/command/order_by_best_command'
require 'bitflyer/cli/command/order_by_twap_command'
require 'bitflyer/cli/command/stop_by_range_command'
require 'bitflyer/cli/command/summary_command'

module Bitflyer
  class CLI < Thor
    desc 'cancel_all', 'cancel all of orders'
    def cancel_all
      CancelAllCommand.new.run
    end

    desc 'counter_trade', 'clear all positions'
    def counter_trade
      CounterTradeCommand.new.run
    end

    desc 'order_by_best', 'create limit order by best price in the board'
    method_option :amount, aliases: 'a', type: :numeric, banner: 'amount', required: true
    method_option :type, aliases: 't', type: :string, banner: 'buy/sell', required: true
    def order_by_best
      OrderByBestCommand.new.run(options)
    end

    desc 'order_by_twap', 'order by using TWAP algorithm'
    method_option :amount, aliases: 'a', type: :numeric, banner: 'amount', required: true
    method_option :type, aliases: 't', type: :string, banner: 'buy/sell', required: true
    method_option :number_of_times, aliases: 'n', type: :numeric, banner: 'N', required: true
    method_option :interval, aliases: 'i', type: :numeric, banner: 'second', required: true
    def order_by_twap
      OrderByTWAPCommand.new.run(options)
    end

    desc 'stop_by_range', 'create stop order by range based on current position'
    method_option :range, aliases: 'r', type: :numeric, banner: 'price range', required: true
    def stop_by_range
      StopByRangeCommand.new.run(options)
    end

    desc 'ifdoco_by_range', 'create IFDOCO order by range based on current price'
    method_option :amount, aliases: 'a', type: :numeric, banner: 'amount', required: true
    method_option :type, aliases: 't', type: :string, banner: 'buy/sell', required: true
    method_option :range, aliases: 'r', type: :numeric, banner: 'price range', required: true
    method_option :percentage, aliases: 'p', type: :numeric, banner: 'price ratio percentage', required: true
    def ifdoco_by_range
      IFDOCOByRangeCommand.new.run(options)
    end

    desc 'summary', 'show current balance information'
    def summary
      SummaryCommand.new.run
    end
  end
end
