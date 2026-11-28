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
        @lookup = ParentOrderLookup.new(client, product_code)
        @classifier = ActiveStopClassifier.new(client, product_code)
      end

      def verify!(offset_side)
        order = @lookup.find_active { |entry| protective_stop?(entry, offset_side) }
        return unless order

        raise Thor::Error, "Active protective stop#{order_identifier(order)} conflicts with the counter trade."
      rescue ParentOrderLookup::LookupFailed, *PersistentHTTPClient::COMMUNICATION_ERRORS => e
        raise Thor::Error, "Could not verify active protective stops: #{e.message}"
      end

      private

      def protective_stop?(order, offset_side)
        case ActiveStopClassifier.from_list(order, offset_side)
        when :not_stop, :opposite_side then false
        when :same_side then true
        else
          parameter = @classifier.resolve(order)
          parameter ? parameter['side'] == offset_side : false
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
