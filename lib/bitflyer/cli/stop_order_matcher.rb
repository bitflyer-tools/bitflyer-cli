# frozen_string_literal: true

require 'bitflyer/cli/parent_order_lookup'

module Bitflyer
  module Cli
    class StopOrderMatcher
      def initialize(client, stop)
        @client = client
        @stop = stop
        @opposite_side = stop.fetch(:side) == 'BUY' ? 'SELL' : 'BUY'
      end

      def match?(order)
        return false unless candidate?(order)

        detail = parent_order_detail(order.fetch('parent_order_id'))
        parameters = detail.fetch('parameters')
        detail['order_method'] == 'SIMPLE' && parameters.one? &&
          @stop.all? { |key, value| parameters.first[key.to_s] == value }
      end

      private

      def candidate?(order)
        order['parent_order_type'] == 'STOP' &&
          order['side'] != @opposite_side &&
          !different_size?(order['size'])
      end

      def different_size?(size)
        (size.is_a?(Integer) || size.is_a?(Float)) && size.finite? && size.positive? && size != @stop.fetch(:size)
      end

      def parent_order_detail(order_id)
        detail = @client.parent_order(parent_order_id: order_id)
        return detail if detail.is_a?(Hash) && detail['parameters'].is_a?(Array)

        raise ParentOrderLookup::LookupFailed, "Failed to look up parent order #{order_id}: #{detail.inspect}"
      end
    end
  end
end
