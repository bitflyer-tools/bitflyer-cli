# frozen_string_literal: true

require 'bitflyer'
require 'io/wait'
require 'openssl'
require 'socket'
require 'timeout'
require 'uri'
require 'websocket/driver'

module Bitflyer
  module Cli
    class RealtimeClient < Bitflyer::Realtime::Client
      # The parent constructor opens a connection before a transport can be supplied.
      def initialize # rubocop:disable Lint/MissingSuper
        @websocket_client = VerifiedWebSocket.new(host: Realtime::SOCKET_HOST, key: nil, secret: nil)
      end

      def shutdown
        @websocket_client.shutdown
      end

      class VerifiedWebSocket < Bitflyer::Realtime::WebSocketClient
        def initialize(**options)
          @lifecycle = Mutex.new
          super
        rescue StandardError
          shutdown
          raise
        end

        def shutdown
          @lifecycle.synchronize do
            @stopped = true
            @monitor&.kill
          end
          @monitor&.join
        ensure
          @websocket_client&.shutdown
        end

        def start_monitoring
          @monitor = super
        end

        def connect
          endpoint = URI.parse("#{@host}/socket.io/?transport=websocket")
          @websocket_client = TLSConnection.new(endpoint)
          @websocket_client.start(self)
        end

        def reconnect
          # A reader handling an error must not wait for a reconnect that is joining it.
          return unless @lifecycle.try_lock

          begin
            return if @stopped || connection_active?

            @websocket_client&.shutdown
            connect
          rescue SocketError, SystemCallError => e
            debug_log e
          ensure
            @lifecycle.unlock
          end
        end

        private

        def connection_active?
          @websocket_client&.open? || @websocket_client&.connecting?
        end
      end

      class TLSConnection
        TCP_CONNECT_TIMEOUT = 10
        TLS_HANDSHAKE_TIMEOUT = 10
        UPGRADE_TIMEOUT = 10

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
          @reader = Thread.new { read_messages(transport) }
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

        def shutdown
          close
          @reader&.join unless @reader == Thread.current
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
          tcp_socket = connect_tcp(endpoint)
          context = OpenSSL::SSL::SSLContext.new
          context.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER, verify_hostname: true)
          socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, context)
          socket.sync_close = true
          socket.hostname = endpoint.host
          Timeout.timeout(TLS_HANDSHAKE_TIMEOUT, SocketError, 'TLS handshake timed out') { socket.connect }
        rescue StandardError
          tcp_socket&.close
          raise
        end

        def connect_tcp(endpoint)
          Timeout.timeout(TCP_CONNECT_TIMEOUT, SocketError, 'TCP connection timed out') do
            TCPSocket.new(endpoint.host, endpoint.port)
          end
        end

        def read_messages(transport)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + UPGRADE_TIMEOUT
          @driver.parse(read_upgrade(deadline)) while connecting?
          @driver.parse(@socket.readpartial(4096)) until @socket.closed?
        rescue IOError, SystemCallError, OpenSSL::SSL::SSLError => e
          close
          transport.handle_close(error: e)
        end

        def read_upgrade(deadline)
          loop do
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            raise IOError, 'WebSocket upgrade timed out' unless remaining.positive?

            case data = @socket.read_nonblock(4096, exception: false)
            when :wait_readable then @socket.to_io.wait_readable(remaining)
            when :wait_writable then @socket.to_io.wait_writable(remaining)
            when nil then raise EOFError
            else return data
            end
          end
        end
      end

      private_constant :TLSConnection, :VerifiedWebSocket
    end
  end
end
