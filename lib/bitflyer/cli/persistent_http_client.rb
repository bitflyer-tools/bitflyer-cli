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
        attr_reader :api_error, :body

        def initialize(status, body)
          super("HTTP request failed (status #{status})")
          @body = body
          @api_error = body.inspect if body.is_a?(Hash)
        end
      end

      def initialize(key, secret) # rubocop:disable Lint/MissingSuper
        @session = Session.new
        @connection = Connection.new(key, secret, @session)
        @ticker_connection = Connection.new(nil, nil, @session)
      end

      def ticker(product_code: 'FX_BTC_JPY')
        @ticker_connection.get('/v1/ticker', product_code: product_code).body
      end

      def child_order_by_acceptance_id(product_code:, child_order_acceptance_id:)
        query = { product_code: product_code, child_order_acceptance_id: child_order_acceptance_id }
        @connection.get('/v1/me/getchildorders', query).body
      end

      def cancel(path, params)
        @connection.raw_post(path, params)
      end

      def close
        @session.close
      end

      # Keeps one Net::HTTP session open across the unsigned ticker connection and the signed order connection.
      class Session
        def http(uri)
          @http ||= Net::HTTP.start(uri.host, uri.port, use_ssl: true, keep_alive_timeout: 30)
        end

        def close
          @http.finish if @http&.started?
        ensure
          @http = nil
        end
      end
      private_constant :Session

      # Reuse the gem's request construction, signing and response parsing.
      class Connection < HTTP::Connection
        def initialize(key, secret, session)
          super(key, secret)
          @session = session
        end

        # Sends a signed POST and returns the raw Net::HTTPResponse, bypassing the empty-body
        # check in #parse_response (cancellation endpoints respond 200 with an empty body).
        def raw_post(path, body)
          request = Net::HTTP::Post.new(path, default_headers.merge('Content-Type' => 'application/json'))
          request.body = JSON.generate(body.compact)
          sign_request(request, path, request.body)
          @session.http(@uri).request(request)
        end

        private

        def execute(request)
          # Net::HTTP reconnects before sending when it detects a closed socket.
          # Its transport retries apply only to idempotent methods, excluding POST.
          response = @session.http(@uri).request(request)
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
