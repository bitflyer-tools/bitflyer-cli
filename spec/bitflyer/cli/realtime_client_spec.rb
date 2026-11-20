require 'spec_helper'
require 'socket'
require 'timeout'

describe Bitflyer::Cli::RealtimeClient do
  let(:server) { TCPServer.new('127.0.0.1', 0) }
  let(:root_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:root) { certificate('Test CA', root_key) }
  let(:server_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:hostname) { 'localhost' }
  let(:transport_class) { described_class.const_get(:VerifiedWebSocket) }

  before do
    stub_const('Bitflyer::Realtime::SOCKET_HOST', "https://localhost:#{server.addr[1]}")
    allow_any_instance_of(transport_class).to receive(:start_monitoring)
    store = OpenSSL::X509::Store.new
    store.add_cert(root)
    stub_const('OpenSSL::SSL::SSLContext::DEFAULT_CERT_STORE', store)
  end

  [SocketError, Errno::ECONNREFUSED].each do |error_class|
    context "when a reconnect raises #{error_class}" do
      let(:connection_error) { error_class.new }

      it 'keeps a pending upgrade and resumes the summary feed after a failed reconnect' do
        ticks = Queue.new
        steps = Queue.new
        upgrades = Queue.new
        disconnected = Queue.new
        monitor = nil
        allow_any_instance_of(transport_class).to receive(:start_monitoring).and_wrap_original do |start|
          monitor = start.call
        end
        allow_any_instance_of(transport_class).to receive(:sleep) do
          ticks << true
          steps.pop
        end

        with_tls_server(connections: 2, upgrades: upgrades, keep_open: true) do |requests, ready|
          stub_responses(stub_persistent_client, positions: [], collateral: { 'collateral' => 0 })
          command = SummaryCommand.new
          transport = command.realtime_client.websocket_client
          on_disconnect = transport.disconnected
          transport.disconnected = lambda do |error|
            on_disconnect.call(error)
            disconnected << error
          end
          connection = transport.websocket_client

          Timeout.timeout(5) do
            expect(requests.pop).to start_with('GET /socket.io/?transport=websocket ')
            ticks.pop
            steps << true
            ticks.pop
            expect(transport.websocket_client).to equal(connection)
            expect(connection).not_to be_open

            upgrades << true
            ready << true
            disconnected.pop
            expect(command.send(:fresh_price)).to be_nil
            failure = connection_error
            allow(TCPSocket).to receive(:new).and_wrap_original do |connect, *args|
              if failure
                error = failure
                failure = nil
                raise error
              end

              connect.call(*args)
            end
            steps << true
            ticks.pop
            expect(transport.websocket_client).to equal(connection)
            expect(monitor).to be_alive

            steps << true
            expect(requests.pop).to start_with('GET /socket.io/?transport=websocket ')
            ticks.pop
            expect(transport.websocket_client).not_to equal(connection)

            upgrades << true
            ready << true
            sleep 0.01 until command.send(:fresh_price) == 1_010_000.0
          end
        ensure
          monitor&.kill&.join
          transport&.websocket_client&.close
        end
      end
    end
  end

  after { server.close }

  it 'times out a stalled TCP dial before starting TLS' do
    stub_const('Bitflyer::Cli::RealtimeClient::TLSConnection::TCP_CONNECT_TIMEOUT', 0.05)
    expect(TCPSocket).to receive(:new).with('localhost', server.addr[1]) { sleep }
    expect(OpenSSL::SSL::SSLSocket).not_to receive(:new)

    Timeout.timeout(1) do
      expect { SummaryCommand.new }.to raise_error(SocketError, 'TCP connection timed out')
    end
  end

  it 'closes the TCP connection when the peer stalls the TLS handshake' do
    stub_const('Bitflyer::Cli::RealtimeClient::TLSConnection::TLS_HANDSHAKE_TIMEOUT', 0.25)
    listener = server
    peer = Thread.new do
      socket = listener.accept
      socket.read
    ensure
      socket&.close
    end

    Timeout.timeout(2) do
      expect { SummaryCommand.new }.to raise_error(SocketError, 'TLS handshake timed out')
      expect(peer.value).not_to be_empty
    end
  ensure
    peer&.kill&.join
  end

  it 'closes a stalled upgrade and delivers executions after reconnecting' do
    stub_const('Bitflyer::Cli::RealtimeClient::TLSConnection::UPGRADE_TIMEOUT', 1)
    upgrades = Queue.new
    disconnected = Queue.new
    executions = Queue.new
    upgrades << false << true

    with_tls_server(connections: 2, upgrades: upgrades) do |requests, ready|
      client = described_class.new
      transport = client.websocket_client
      transport.disconnected = ->(error) { disconnected << error }
      client.executions_fx_btc_jpy = ->(batch) { executions << batch }

      Timeout.timeout(5) do
        expect(requests.pop).to start_with('GET /socket.io/?transport=websocket ')
        expect(disconnected.pop).to have_attributes(message: 'WebSocket upgrade timed out')
        transport.reconnect
        expect(requests.pop).to start_with('GET /socket.io/?transport=websocket ')
        ready << true
        expect(executions.pop).to eq([{ 'price' => 1_010_000 }])
      end
    ensure
      transport&.websocket_client&.close
    end
  end

  it 'delivers executions from a trusted peer for the endpoint hostname' do
    with_tls_server(keep_open: true) do |requests, ready|
      stub_responses(stub_persistent_client, positions: [], collateral: { 'collateral' => 0 })
      command = SummaryCommand.new
      ready << true
      Timeout.timeout(5) do
        expect(requests.pop).to start_with('GET /socket.io/?transport=websocket ')
        sleep 0.01 until command.send(:fresh_price) == 1_010_000.0
      end
    ensure
      command&.realtime_client&.websocket_client&.websocket_client&.close
    end
  end

  context 'with an untrusted certificate' do
    it 'fails before sending the WebSocket upgrade request' do
      other_key = OpenSSL::PKey::RSA.new(2048)
      other_root = certificate('Untrusted CA', other_key)
      expect_rejected(issuer: other_root, issuer_key: other_key)
    end
  end

  context 'with a certificate for another hostname' do
    let(:hostname) { 'other.example' }

    it 'fails before sending the WebSocket upgrade request' do
      expect_rejected
    end
  end

  def expect_rejected(**issuer_options)
    with_tls_server(**issuer_options) do |requests|
      expect { SummaryCommand.new }.to raise_error(OpenSSL::SSL::SSLError)
      expect(Timeout.timeout(5) { requests.pop }).to be_nil
    end
  end

  def with_tls_server(issuer: root, issuer_key: root_key, connections: 1, upgrades: nil, keep_open: false)
    context = OpenSSL::SSL::SSLContext.new
    context.cert = certificate(hostname, server_key, issuer: issuer, issuer_key: issuer_key)
    context.key = server_key
    requests = Queue.new
    ready = Queue.new
    worker = Thread.new do
      connections.times do |index|
        serve_execution(context, requests, ready, upgrades, keep_open && index == connections - 1)
      end
    end
    yield requests, ready
  ensure
    worker&.kill&.join
  end

  def serve_execution(context, requests, ready, upgrades, keep_open)
    socket = OpenSSL::SSL::SSLServer.new(server, context).accept
    request = socket.gets("\r\n\r\n")
    requests << request
    handshake = WebSocket::Handshake::Server.new
    handshake << request
    if upgrades&.pop == false
      socket.write("HTTP/1.1 101 Switching Protocols\r\n")
      return socket.read
    end
    socket.write(handshake.to_s)
    ready.pop
    socket.write(WebSocket::Frame::Outgoing::Server.new(data: '0{}', type: :text, version: handshake.version).to_s)
    # Wait for the client to register its callback before sending the execution.
    socket.readpartial(4096)
    payload = '42["lightning_executions_FX_BTC_JPY",[{"price":1010000}]]'
    socket.write(WebSocket::Frame::Outgoing::Server.new(data: payload, type: :text, version: handshake.version).to_s)
    socket.read if keep_open
  rescue OpenSSL::SSL::SSLError
    requests << nil
  ensure
    socket&.close
  end

  def certificate(name, key, issuer: nil, issuer_key: key)
    OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version = 2
      cert.serial = issuer ? 2 : 1
      cert.subject = OpenSSL::X509::Name.new([['CN', name]])
      cert.issuer = issuer ? issuer.subject : cert.subject
      cert.public_key = key.public_key
      cert.not_before = Time.now - 60
      cert.not_after = Time.now + 3600
      extensions = OpenSSL::X509::ExtensionFactory.new(issuer || cert, cert)
      extension = issuer ? ['subjectAltName', "DNS:#{name}"] : ['basicConstraints', 'CA:TRUE', true]
      cert.add_extension(extensions.create_extension(*extension))
      cert.sign(issuer_key, OpenSSL::Digest.new('SHA256'))
    end
  end
end
