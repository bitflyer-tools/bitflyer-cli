# frozen_string_literal: true

require 'bitflyer/cli/parent_order_lookup'

module Bitflyer
  module Cli
    class StopOrderMatcher
      def initialize(client, stop)
        @client = client
        @stop = stop
      end

      def classify(order)
        return unless stop_candidate?(order)

        detail = parent_order_detail(order.fetch('parent_order_id'))
        parameters = detail.fetch('parameters')
        return unless detail['order_method'] == 'SIMPLE' && parameters.one?

        parameter = parameters.first
        return unless same_scope?(parameter)

        @stop.all? { |key, value| parameter[key.to_s] == value } ? :exact : :conflict
      end

      private

      def same_scope?(parameter)
        %i[product_code condition_type side].all? { |key| parameter[key.to_s] == @stop.fetch(key) }
      end

      def stop_candidate?(order)
        order['parent_order_type'] == 'STOP' &&
          !opposite_side?(order['side'], @stop.fetch(:side))
      end

      def opposite_side?(side, expected_side)
        side == (expected_side == 'BUY' ? 'SELL' : 'BUY')
      end

      def parent_order_detail(order_id)
        detail = @client.parent_order(parent_order_id: order_id)
        return detail if detail.is_a?(Hash) && detail['parameters'].is_a?(Array)

        raise ParentOrderLookup::LookupFailed, "Failed to look up parent order #{order_id}: #{detail.inspect}"
      end
    end
  end
end
