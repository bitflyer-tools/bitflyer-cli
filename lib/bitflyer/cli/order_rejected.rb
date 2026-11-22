# frozen_string_literal: true

module Bitflyer
  module Cli
    class OrderRejected < StandardError
      class Unverified < StandardError; end

      def self.check!(response, acceptance_key)
        acceptance_id = response[acceptance_key] if response.is_a?(Hash)
        return if acceptance_id.is_a?(String) && acceptance_id.match?(/[^[:space:]]/)

        raise Unverified, 'Could not verify order acceptance.' unless acceptance_id.nil? && rejected?(response)

        message = response['error_message'].to_s
        raise self, message.empty? ? "Order rejected: #{response.inspect}" : message
      end

      def self.rejected?(response)
        status = response['status'] if response.is_a?(Hash)
        status.is_a?(Integer) && status.negative?
      end
      private_class_method :rejected?
    end
  end
end
