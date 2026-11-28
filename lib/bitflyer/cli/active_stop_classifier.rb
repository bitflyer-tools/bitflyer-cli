# frozen_string_literal: true

require 'bitflyer/cli/parent_order_lookup'
require 'bitflyer/cli/terminal_text'

module Bitflyer
  module Cli
    # Shared between StopOrderMatcher and ProtectiveStopCheck so both agree on
    # when a list row is enough to classify an active order and when its
    # detail must be consulted instead.
    class ActiveStopClassifier
      NON_STOP_TYPES = %w[LIMIT MARKET STOP_LIMIT TRAIL IFD OCO IFDOCO].freeze

      def self.from_list(order, expected_side)
        type, side = order.values_at('parent_order_type', 'side')
        return :not_stop if NON_STOP_TYPES.include?(type)
        return :ambiguous unless type == 'STOP' && %w[BUY SELL].include?(side)

        side == expected_side ? :same_side : :opposite_side
      end

      def initialize(client, product_code)
        @client = client
        @product_code = product_code
      end

      # Returns the sole STOP parameter (string keys) for a standalone order on
      # @product_code, or nil if the detail shows it isn't one.
      def resolve(order)
        detail = parent_order_detail(order.fetch('parent_order_id'))
        parameters = detail.fetch('parameters')
        return unless detail['order_method'] == 'SIMPLE' && parameters.one?

        parameter = parameters.first
        parameter if parameter['product_code'] == @product_code && parameter['condition_type'] == 'STOP'
      end

      private

      def parent_order_detail(order_id)
        detail = @client.parent_order(parent_order_id: order_id)
        return detail if detail.is_a?(Hash) && detail['parameters'].is_a?(Array)

        escaped_id = TerminalText.escape(order_id.to_s)
        raise ParentOrderLookup::LookupFailed, "Failed to look up parent order #{escaped_id}: #{detail.inspect}"
      end
    end
  end
end
