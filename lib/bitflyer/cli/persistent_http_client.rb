# frozen_string_literal: true

require 'bitflyer'

module Bitflyer
  module Cli
    class PersistentHTTPClient < HTTP::Private::Client
      PostResponse = Struct.new(:status, :body)

      COMMUNICATION_ERRORS = [
        Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
      ].freeze

      class GetResponseError < Net::HTTPBadResponse
        attr_reader :api_error, :api_message

        def initialize(status, body)
          super("HTTP request failed (status #{status})")
          return unless body.is_a?(Hash)

          @api_error = body.inspect
          @api_message = body['error_message'].to_s
        end
      end

      def initialize(key, secret) # rubocop:disable Lint/MissingSuper
        @connection = Connection.new(key, secret)
      end

      def child_order_by_acceptance_id(product_code:, child_order_acceptance_id:)
        query = { product_code: product_code, child_order_acceptance_id: child_order_acceptance_id }
        @connection.get('/v1/me/getchildorders', query).body
      end

      def close
        @connection.close
      end

      # Reuse the gem's request construction, signing and response parsing.
      class Connection < HTTP::Connection
        def close
          @http.finish if @http&.started?
        ensure
          @http = nil
        end

        private

        def execute(request)
          @http ||= Net::HTTP.start(@uri.host, @uri.port, use_ssl: true, keep_alive_timeout: 30)
          # Net::HTTP reconnects before sending when it detects a closed socket.
          # Its transport retries apply only to idempotent methods, excluding POST.
          response = @http.request(request)
          parse_response(request, response)
        end

        def parse_response(request, response)
          body = response.body
          status = response.code.to_i
          raise Net::HTTPBadResponse, "Empty HTTP response body (status #{status})" if body.to_s.empty?

          parsed_body = parse_body(body)
          return PostResponse.new(status, parsed_body) if request.is_a?(Net::HTTP::Post)

          return parsed_body if status.between?(200, 299)

          raise GetResponseError.new(status, parsed_body)
        end
      end
      private_constant :Connection
    end
  end
end
