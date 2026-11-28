# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/active_stop_classifier'
require 'bitflyer/cli/parent_order_lookup'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/terminal_text'

module Bitflyer
  module Cli
    class ProtectiveStopCheck
      def initialize(client, product_code)
        @product_code = product_code
        @lookup = ParentOrderLookup.new(client, product_code)
        @classifier = ActiveStopClassifier.new(client, product_code)
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
        return verify_ifdoco!(order, offset_side) if order['parent_order_type'] == 'IFDOCO'

        case ActiveStopClassifier.from_list(order, offset_side)
        when :not_stop, :opposite_side then false
        when :same_side then true
        else
          detail = @classifier.parent_order_detail(order.fetch('parent_order_id'))
          return verify_ifdoco!(order, offset_side, detail) if detail['order_method'] == 'IFDOCO'

          parameter = @classifier.standalone_stop(detail)
          parameter ? parameter['side'] == offset_side : false
        end
      end

      def verify_ifdoco!(order, offset_side, detail = nil)
        identifier = order_identifier(order)
        detail ||= @classifier.parent_order_detail(order['parent_order_id']) if identifier
        raise Thor::Error, "Could not verify active IFDOCO exits#{identifier}." unless valid_ifdoco_detail?(detail)

        # Active parent details describe configured legs, including conditional exits awaiting a trigger.
        return false if detail['parameters'].drop(1).none? { |leg| leg['side'] == offset_side }

        raise Thor::Error, "Active IFDOCO exit#{identifier} can conflict with the counter trade."
      rescue ParentOrderLookup::LookupFailed, *PersistentHTTPClient::COMMUNICATION_ERRORS
        raise Thor::Error, "Could not verify active IFDOCO exits#{identifier}."
      end

      def valid_ifdoco_detail?(detail)
        return false unless detail && detail['order_method'] == 'IFDOCO'

        legs = detail.fetch('parameters')
        legs.size == 3 && legs.all? do |leg|
          leg.is_a?(Hash) && leg['product_code'] == @product_code && %w[BUY SELL].include?(leg['side'])
        end
      end

      def order_identifier(order)
        id = order.values_at('parent_order_id', 'parent_order_acceptance_id').find do |value|
          value.is_a?(String) && !value.strip.empty?
        end
        " (#{TerminalText.escape(id)})" if id
      end
    end
  end
end
