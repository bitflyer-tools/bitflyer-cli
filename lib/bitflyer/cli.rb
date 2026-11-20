# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/command/cancel_all_command'
require 'bitflyer/cli/command/cancel_order_command'
require 'bitflyer/cli/command/counter_trade_command'
require 'bitflyer/cli/command/executions_command'
require 'bitflyer/cli/command/ifdoco_by_range_command'
require 'bitflyer/cli/command/open_orders_command'
require 'bitflyer/cli/command/order_by_best_command'
require 'bitflyer/cli/command/order_by_twap_command'
require 'bitflyer/cli/command/stop_by_range_command'
require 'bitflyer/cli/command/summary_command'
require 'bitflyer/cli/version'

module Bitflyer
  module Cli
    class Runner < Thor
      def self.exit_on_failure?
        true
      end

      desc 'cancel_all', 'cancel all of orders'
      def cancel_all
        CancelAllCommand.new.run
      end

      desc 'cancel_order TYPE ID', 'request cancellation of one child order or parent strategy'
      long_desc 'Use child or parent as TYPE and copy the order ID from open_orders. ' \
                'Canceling a parent strategy also cancels its associated orders and requires --confirm-parent.'
      method_option :confirm_parent, type: :boolean, default: false,
                                     desc: 'Confirm cancellation of the parent strategy and its associated orders'
      def cancel_order(type = nil, id = nil)
        CancelOrderCommand.new.run(type, id, confirm_parent: options[:confirm_parent])
      end

      desc 'counter_trade', 'clear all positions'
      def counter_trade
        CounterTradeCommand.new.run
      end

      desc 'executions', 'show recent account executions for FX_BTC_JPY'
      method_option :child_order_id, type: :string, desc: 'Child order ID from open_orders'
      method_option :child_order_acceptance_id, type: :string, desc: 'Child order acceptance ID from TWAP output'
      def executions
        ExecutionsCommand.new.run(child_order_id: options[:child_order_id],
                                  child_order_acceptance_id: options[:child_order_acceptance_id])
      end

      desc 'open_orders', 'show active child orders and parent strategies'
      def open_orders
        OpenOrdersCommand.new.run
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
        counts = OrderByTWAPCommand.new.run(options)
        exit 1 if counts[:rejected].positive? || counts[:unverified].positive?
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
end
