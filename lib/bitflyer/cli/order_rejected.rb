# frozen_string_literal: true

module Bitflyer
  module Cli
    class OrderRejected < StandardError
      class Unverified < StandardError; end

      def self.accepted?(status, acceptance_id, body)
        status.between?(200, 299) && acceptance_id?(acceptance_id) && !error_fields?(body)
      end

      def self.acceptance_id?(id)
        id.is_a?(String) && !id.strip.empty?
      end

      def self.negative_status?(body)
        status = body['status']
        status.is_a?(Numeric) && status.negative?
      end

      def self.check!(response, acceptance_key)
        raise Unverified, 'Could not verify order acceptance.' unless response.is_a?(Hash)

        acceptance_id = response[acceptance_key]
        return if valid_acceptance?(acceptance_id, response)

        raise Unverified, 'Could not verify order acceptance.' unless acceptance_id.nil? && rejected?(response)

        message = response['error_message'].to_s
        raise self, message.empty? ? "Order rejected: #{response.inspect}" : message
      end

      def self.valid_acceptance?(acceptance_id, body)
        acceptance_id?(acceptance_id) && acceptance_id.match?(/[^[:space:]]/) && !error_fields?(body)
      end
      private_class_method :valid_acceptance?

      def self.error_fields?(body)
        message = body['error_message']
        negative_status?(body) || (message.is_a?(String) && !message.strip.empty?)
      end
      private_class_method :error_fields?

      def self.rejected?(response)
        response['status'].is_a?(Integer) && negative_status?(response)
      end
      private_class_method :rejected?
    end
  end
end
