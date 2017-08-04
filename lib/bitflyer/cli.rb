require 'thor'
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
  end
end
