# frozen_string_literal: true

require 'bitflyer/cli/parent_order_lookup'

module Bitflyer
  module Cli
    class ActiveStopLookup
      def initialize(client, lookup)
        @client = client
        @lookup = lookup
      end

      def find(stop)
        conflicts = []
        exact = @lookup.find('ACTIVE') do |entry|
          parameter = standalone_stop(entry, stop.fetch(:side))
          next false unless parameter && same_stop_scope?(parameter, stop)
          next true if stop.all? { |key, value| parameter[key.to_s] == value }

          conflicts << entry.fetch('parent_order_id')
          false
        end
        [exact, conflicts]
      end

      private

      def standalone_stop(order, side)
        return unless order['parent_order_type'] == 'STOP'
        return if order['side'] == (side == 'BUY' ? 'SELL' : 'BUY')

        detail = parent_order_detail(order.fetch('parent_order_id'))
        parameters = detail.fetch('parameters')
        parameters.first if detail['order_method'] == 'SIMPLE' && parameters.one?
      end

      def same_stop_scope?(parameter, stop)
        %i[product_code condition_type side].all? { |key| parameter[key.to_s] == stop.fetch(key) }
      end

      def parent_order_detail(order_id)
        detail = @client.parent_order(parent_order_id: order_id)
        return detail if detail.is_a?(Hash) && detail['parameters'].is_a?(Array)

        raise ParentOrderLookup::LookupFailed, "Failed to look up parent order #{order_id}: #{detail.inspect}"
      end
    end
  end
end
