# frozen_string_literal: true

module Bitflyer
  module Cli
    class OrderRejected < StandardError
      def self.accepted?(status, acceptance_id, body)
        status.between?(200, 299) && acceptance_id.is_a?(String) && !acceptance_id.strip.empty? &&
          !error_fields?(body)
      end

      def self.error_fields?(body)
        message = body['error_message']
        negative_status?(body) || (message.is_a?(String) && !message.strip.empty?)
      end

      private_class_method :error_fields?

      def self.negative_status?(body)
        status = body['status']
        status.is_a?(Numeric) && status.negative?
      end

      def self.check!(response, acceptance_key)
        return if response.is_a?(Hash) && !response[acceptance_key].nil?

        message = response['error_message'].to_s if response.is_a?(Hash)
        raise self, message.to_s.empty? ? "Order rejected: #{response.inspect}" : message
      end
    end
  end
end
