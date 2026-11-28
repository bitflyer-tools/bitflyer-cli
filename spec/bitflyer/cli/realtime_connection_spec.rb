# frozen_string_literal: true

require 'spec_helper'

describe Bitflyer::Cli::RealtimeClient, 'WebSocket connection setup' do
  it 'closes the TLS socket and propagates a failed upgrade request' do
    tcp_socket = instance_double(TCPSocket)
    tls_socket = instance_double(OpenSSL::SSL::SSLSocket, connect: nil, close: nil)
    allow(tls_socket).to receive(:sync_close=).with(true)
    allow(tls_socket).to receive(:hostname=)
    allow(TCPSocket).to receive(:new).and_return(tcp_socket)
    allow(OpenSSL::SSL::SSLSocket).to receive(:new).with(tcp_socket, instance_of(OpenSSL::SSL::SSLContext))
                                                   .and_return(tls_socket)
    allow(tls_socket).to receive(:write).with(a_string_starting_with('GET /socket.io/?transport=websocket '))
                                        .and_raise(Errno::EPIPE)

    expect { described_class.new }.to raise_error(Errno::EPIPE)
    expect(tls_socket).to have_received(:close).at_least(:once)
  end
end
