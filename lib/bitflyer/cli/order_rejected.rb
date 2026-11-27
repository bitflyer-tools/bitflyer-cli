# frozen_string_literal: true

require 'bitflyer/cli/terminal_text'

module Bitflyer
  module Cli
    class OrderRejected < StandardError
      class Unverified < StandardError; end

      def self.classify(response, acceptance_key)
        body = response.body
        return :unverified unless body.is_a?(Hash)

        status = response.status
        acceptance_id = body[acceptance_key]
        success = status.between?(200, 299)
        return :accepted if success && valid_acceptance?(acceptance_id, body)
        return :rejected if (success || client_rejection_status?(status)) && rejected?(acceptance_id, body)

        :unverified
      end

      def self.acceptance_id?(id)
        id.is_a?(String) && !id.strip.empty? && id.match?(/[^[:space:]]/)
      end

      def self.raise_rejection!(response)
        message = response['error_message'].to_s
        raise self, message.empty? ? "Order rejected: #{response.inspect}" : TerminalText.escape(message)
      end

      def self.valid_acceptance?(acceptance_id, body)
        acceptance_id?(acceptance_id) && !error_fields?(body)
      end
      private_class_method :valid_acceptance?

      def self.error_fields?(body)
        message = body['error_message']
        negative_status?(body) || (message.is_a?(String) && !message.strip.empty?)
      end
      private_class_method :error_fields?

      def self.rejected?(acceptance_id, body)
        acceptance_id.nil? && body['status'].is_a?(Integer) && negative_status?(body)
      end
      private_class_method :rejected?

      def self.negative_status?(body)
        status = body['status']
        status.is_a?(Numeric) && status.negative?
      end
      private_class_method :negative_status?

      def self.client_rejection_status?(status)
        status.between?(400, 499) && status != 408
      end
      private_class_method :client_rejection_status?
    end
  end
end
