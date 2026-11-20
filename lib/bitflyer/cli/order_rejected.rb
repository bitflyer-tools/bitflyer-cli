# frozen_string_literal: true

module Bitflyer
  module Cli
    class OrderRejected < StandardError
      def self.check!(response, acceptance_key)
        return if response.is_a?(Hash) && !response[acceptance_key].nil?

        message = response['error_message'].to_s if response.is_a?(Hash)
        raise self, message.to_s.empty? ? "Order rejected: #{response.inspect}" : message
      end
    end
  end
end
