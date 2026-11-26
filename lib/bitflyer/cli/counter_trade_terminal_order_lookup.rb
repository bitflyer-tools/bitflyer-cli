# frozen_string_literal: true

require 'bigdecimal'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/terminal_text'

module Bitflyer
  module Cli
    class CounterTradeTerminalOrderLookup
      ACCEPTANCE_ID = 'child_order_acceptance_id'
      TERMINAL_STATES = %w[COMPLETED CANCELED EXPIRED REJECTED].freeze

      def initialize(client, product_code)
        @client = client
        @product_code = product_code
      end

      def executed_size(submission, id)
        order = terminal_order(submission, id)
        return unless order

        size = BigDecimal(order['executed_size'].to_s, exception: false)
        size if size&.finite? && !size.negative?
      end

      private

      def terminal_order(submission, id)
        orders = fetch_orders(id)
        return unless orders.is_a?(Array)

        require_absent_order_reconciliation(submission, id) if orders.empty?
        matching_terminal_order(orders, id)
      rescue *PersistentHTTPClient::COMMUNICATION_ERRORS
        nil
      end

      def fetch_orders(id)
        @client.child_order_by_acceptance_id(product_code: @product_code, child_order_acceptance_id: id)
      end

      def matching_terminal_order(orders, id)
        return unless orders.one?

        order = orders.first
        return unless order.is_a?(Hash) && order[ACCEPTANCE_ID] == id

        order if TERMINAL_STATES.include?(order['child_order_state'])
      end

      def require_absent_order_reconciliation(submission, id)
        submission.require_reconciliation(
          "Previous counter trade (#{TerminalText.escape(id)}) is absent from the order history lookup. bitFlyer " \
          'omits a canceled, expired, or rejected order from this endpoint when it never received a fill, ' \
          'so automatic reconciliation cannot establish the outcome.'
        )
      end
    end
  end
end
