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

      def self.check_submission!(response, acceptance_key)
        status = response.status
        body = response.body
        return check!(body, acceptance_key) if status.between?(200, 299)

        raise_rejection!(body) if status.between?(400, 499) && body.is_a?(Hash) && rejected?(body[acceptance_key], body)

        raise Unverified, "Could not verify order acceptance (HTTP #{status})."
      end

      def self.check!(response, acceptance_key)
        raise Unverified, 'Could not verify order acceptance.' unless response.is_a?(Hash)

        acceptance_id = response[acceptance_key]
        return if valid_acceptance?(acceptance_id, response)

        raise Unverified, 'Could not verify order acceptance.' unless rejected?(acceptance_id, response)

        raise_rejection!(response)
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
