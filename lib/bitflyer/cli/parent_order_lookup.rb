# frozen_string_literal: true

module Bitflyer
  module Cli
    class ParentOrderLookup
      class LookupFailed < StandardError; end
      class RequestLimitExceeded < StandardError; end

      PAGE_SIZE = 100

      def initialize(client, product_code)
        @client = client
        @product_code = product_code
      end

      def find(state, before_page: nil, &match_order)
        before = nil
        loop do
          before_page&.call
          orders = parent_orders(state, before)
          match = orders.find(&match_order)
          return match if match
          return if orders.size < PAGE_SIZE

          before = next_cursor(orders, before, state)
        end
      end

      def find_across_states(states, max_requests:, &match_order)
        before_page = lambda do
          raise RequestLimitExceeded if max_requests.zero?

          max_requests -= 1
        end
        states.each do |state|
          order = find(state, before_page: before_page, &match_order)
          return [state, order] if order
        end
        nil
      end

      private

      def next_cursor(orders, before, state)
        ids = orders.map { |order| order['id'] }
        if ids.all? { |id| id.is_a?(Integer) && id.positive? }
          cursor = ids.min
          return cursor if before.nil? || cursor < before
        end

        raise LookupFailed, "Could not paginate #{state.downcase} parent orders."
      end

      def parent_orders(state, before)
        orders = @client.parent_orders(
          product_code: @product_code, parent_order_state: state, count: PAGE_SIZE, before: before
        )
        return orders if orders.is_a?(Array) && orders.all?(Hash)

        raise LookupFailed, "Failed to look up #{state.downcase} parent orders: #{orders.inspect}"
      end
    end
  end
end
