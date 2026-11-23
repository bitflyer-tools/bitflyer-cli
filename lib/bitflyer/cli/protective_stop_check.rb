# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/parent_order_lookup'
require 'bitflyer/cli/persistent_http_client'

module Bitflyer
  module Cli
    class ProtectiveStopCheck
      ORDER_TYPES = %w[LIMIT MARKET STOP STOP_LIMIT TRAIL IFD OCO IFDOCO].freeze

      def initialize(client, product_code)
        @lookup = ParentOrderLookup.new(client, product_code)
      end

      def verify!(offset_side)
        order = @lookup.find('ACTIVE') { |entry| protective_stop?(entry, offset_side) }
        return unless order

        raise Thor::Error, "Active protective stop#{order_identifier(order)} conflicts with the counter trade."
      rescue ParentOrderLookup::LookupFailed, *PersistentHTTPClient::COMMUNICATION_ERRORS => e
        raise Thor::Error, "Could not verify active protective stops: #{e.message}"
      end

      private

      def protective_stop?(order, offset_side)
        type, side = order.values_at('parent_order_type', 'side')
        if ORDER_TYPES.include?(type)
          return false unless type == 'STOP'
          return side == offset_side if %w[BUY SELL].include?(side)
        end

        raise Thor::Error, "Could not verify active parent order#{order_identifier(order)}."
      end

      def order_identifier(order)
        id = order.values_at('parent_order_id', 'parent_order_acceptance_id').find do |value|
          value.is_a?(String) && !value.strip.empty?
        end
        " (#{id})" if id
      end
    end
  end
end
