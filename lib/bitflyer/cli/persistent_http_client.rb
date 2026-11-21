# frozen_string_literal: true

require 'bitflyer'

module Bitflyer
  module Cli
    class PersistentHTTPClient < HTTP::Private::Client
      PostResponse = Struct.new(:status, :body)

      def initialize(key, secret) # rubocop:disable Lint/MissingSuper
        @connection = Connection.new(key, secret)
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
          body = response.body
          raise Net::HTTPBadResponse, "Empty HTTP response body (status #{response.code})" if body.nil? || body.empty?

          parsed_body = parse_body(body)
          return parsed_body unless request.is_a?(Net::HTTP::Post)

          PostResponse.new(response.code.to_i, parsed_body)
        end
      end
      private_constant :Connection
    end
  end
end
