require 'thor'
require 'bitflyer/cli/command/cancel_all_command'
require 'bitflyer/cli/command/counter_trade_command'
require 'bitflyer/cli/command/summary_command'
require 'bitflyer/cli/command/order_by_best_command'

module Bitflyer
  class CLI < Thor
    desc 'summary', 'show current balance information'
    def summary
      SummaryCommand.new.run
    end

    desc 'order_by_best', 'create limit order by best price in the board'
    method_option :amount, aliases: 'a', type: :numeric, banner: 'amount'
    method_option :type, aliases: 't', type: :string, banner: 'buy or sell'
    def order_by_best
      OrderByBestCommand.new.run(options)
    end

    desc 'counter_trade', 'clear all positions'
    def counter_trade
      CounterTradeCommand.new.run
    end

    desc 'cancel_all', 'cancel all of orders'
    def cancel_all
      CancelAllCommand.new.run
    end
  end
end
