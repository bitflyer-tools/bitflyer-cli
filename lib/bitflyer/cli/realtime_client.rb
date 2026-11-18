# frozen_string_literal: true

require 'bitflyer'
require 'openssl'
require 'socket'
require 'uri'
require 'websocket/driver'

module Bitflyer
  module Cli
    class RealtimeClient < Bitflyer::Realtime::Client
      # The parent constructor opens a connection before a transport can be supplied.
      def initialize # rubocop:disable Lint/MissingSuper
        @websocket_client = VerifiedWebSocket.new(host: Realtime::SOCKET_HOST, key: nil, secret: nil)
      end

      class VerifiedWebSocket < Bitflyer::Realtime::WebSocketClient
        def connect
          endpoint = URI.parse("#{@host}/socket.io/?transport=websocket")
          @websocket_client = TLSConnection.new(endpoint)
          @websocket_client.start(self)
        end

        def reconnect
          return if @websocket_client&.connecting?

          super
        end
      end

      class TLSConnection
        attr_reader :url

        def initialize(endpoint)
          @url = URI::Generic.build(
            scheme: 'wss', host: endpoint.host, port: endpoint.port, path: endpoint.path, query: endpoint.query
          ).to_s
          @socket = connect_tls(endpoint)
          @driver = WebSocket::Driver.client(self)
        end

        def start(transport)
          register_handlers(transport)
          @driver.start
          Thread.new { read_messages(transport) }
        rescue StandardError
          close
          raise
        end

        def open?
          !@socket.closed? && @driver.state == :open
        end

        def connecting?
          !@socket.closed? && @driver.state == :connecting
        end

        def send(message)
          @driver.text(message) if open?
        end

        def write(data)
          @socket.write(data)
        end

        def close
          @socket.close
        end

        private

        def register_handlers(transport)
          @driver.on(:message) { |payload| transport.handle_message(payload: payload) }
          @driver.on(:error) { |error| transport.handle_error(error: error) }
          @driver.on(:close) do |event|
            close
            transport.handle_close(error: event)
          end
        end

        def connect_tls(endpoint)
          context = OpenSSL::SSL::SSLContext.new
          context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER, verify_hostname: true)
          tcp_socket = TCPSocket.new(endpoint.host, endpoint.port)
          socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, context)
          socket.sync_close = true
          socket.hostname = endpoint.host
          socket.connect
        rescue StandardError
          tcp_socket&.close
          raise
        end

        def read_messages(transport)
          @driver.parse(@socket.readpartial(4096)) until @socket.closed?
        rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
          close
          transport.handle_close(error: e)
        end
      end

      private_constant :TLSConnection, :VerifiedWebSocket
    end
  end
end
