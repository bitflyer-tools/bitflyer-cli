# frozen_string_literal: true

require 'bitflyer/cli/parent_order_lookup'
require 'bitflyer/cli/model/position'

module Bitflyer
  module Cli
    class StopOrderMatcher
      def initialize(client, stop)
        @client = client
        @stop = stop
      end

      def matches?(order)
        return false unless stop_candidate?(order)

        detail = parent_order_detail(order.fetch('parent_order_id'))
        parameters = detail.fetch('parameters')
        detail['order_method'] == 'SIMPLE' && parameters.one? &&
          @stop.all? { |key, value| parameters.first[key.to_s] == value }
      end

      private

      def stop_candidate?(order)
        order['parent_order_type'] == 'STOP' &&
          !opposite_side?(order['side'], @stop.fetch(:side)) &&
          !different_size?(order['size'], @stop.fetch(:size))
      end

      def opposite_side?(side, expected_side)
        side == (expected_side == 'BUY' ? 'SELL' : 'BUY')
      end

      def different_size?(size, expected_size)
        raw = size.to_s
        return false unless Position::DECIMAL.match?(raw)

        listed_size = Float(raw, exception: false)
        listed_size&.finite? && listed_size.positive? && listed_size != expected_size
      end

      def parent_order_detail(order_id)
        detail = @client.parent_order(parent_order_id: order_id)
        return detail if detail.is_a?(Hash) && detail['parameters'].is_a?(Array)

        raise ParentOrderLookup::LookupFailed, "Failed to look up parent order #{order_id}: #{detail.inspect}"
      end
    end
  end
end
