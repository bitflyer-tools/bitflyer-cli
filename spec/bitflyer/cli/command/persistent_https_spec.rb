require 'spec_helper'

describe 'Persistent exchange HTTPS' do
  let(:order_path) { '/v1/me/sendchildorder' }
  let(:positions_path) { '/v1/me/getpositions?product_code=FX_BTC_JPY' }
  let(:collateral_path) { '/v1/me/getcollateral' }
  let(:acceptance) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before { stub_credentials }
  after { @server&.stop }

  it 'sends signed TWAP slices on one TLS connection and closes it on exit' do
    start_server { [acceptance, false] }
    command = OrderByTWAPCommand.new
    now = Time.now
    allow(Time).to receive(:now).and_return(now, now + 1, now + 2)

    expect { run_twap(command, 3) }.to output(/3 accepted, 0 rejected/).to_stdout

    expect(closed_connection).to eq(1)
    expect(@server.requests.map { |id, method, path| [id, method, path] }).to eq([[1, 'POST', order_path]] * 3)
    expect(@server.requests.map { |request| request[3].fetch('access-timestamp') })
      .to eq(3.times.map { |offset| (now.to_i + offset).to_s })
    expect_signed_requests
  end

  it 'reconnects for the next TWAP slice when the server closes the connection' do
    start_server { |_path, number| [acceptance, number == 1] }

    expect { run_twap(OrderByTWAPCommand.new, 3) }.to output(/3 accepted, 0 rejected/).to_stdout

    expect([closed_connection, closed_connection]).to eq([1, 2])
    expect(@server.requests.map(&:first)).to eq([1, 2, 2])
  end

  it 'reports partial results after a lost order response without replaying that slice' do
    start_server { |_path, number| [number == 2 ? nil : acceptance, false] }
    command = OrderByTWAPCommand.new

    expect { run_twap(command, 3) }.to output(/1 accepted, 0 rejected, 1 unverified, 1 unattempted\./).to_stdout
    expect(closed_connection).to eq(1)
    expect(@server.requests.map(&:first)).to eq([1, 1])

    expect { run_twap(command, 1) }.to output(/1 accepted, 0 rejected/).to_stdout
    expect(closed_connection).to eq(2)
    expect(@server.requests.map(&:first)).to eq([1, 1, 2])
  end

  it 'uses one TLS connection for startup and multiple summary refreshes and closes it on interrupt' do
    start_server { |path| [path == positions_path ? [] : { collateral: 50_000 }, false] }
    allow(stub_realtime_client).to receive(:disconnected=)
    command = SummaryCommand.new
    refreshed = Queue.new
    elapsed = 0
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_wrap_original do |clock, id|
      clock.call(id) + elapsed
    end
    allow(command).to receive(:sleep).with(5) do |seconds|
      if elapsed == 10
        refreshed << true
        Thread.stop
      end
      elapsed += seconds
    end
    allow(command).to receive(:sleep).with(0.1) do
      Timeout.timeout(5) { refreshed.pop }
      raise Interrupt
    end

    expect { command.run }.to output(/Position: 0/).to_stdout

    expect(closed_connection).to eq(1)
    expect(@server.requests.map { |id, method, path| [id, method, path] })
      .to eq([[1, 'GET', positions_path], [1, 'GET', collateral_path]] * 3)
    expect_signed_requests
  end

  def run_twap(command, slices)
    command.run(thor_options(amount: 0.01, type: 'buy', number_of_times: slices, interval: 0))
  end

  def start_server(&reply)
    @server = KeepAliveHTTPSServer.new(&reply)
    store = OpenSSL::X509::Store.new
    store.add_cert(@server.certificate)
    stub_const('Bitflyer::HTTP::BASE_URL', @server.url)
    allow(Net::HTTP).to receive(:start).and_wrap_original do |original, host, port, **options|
      expect([host, port]).to eq(['127.0.0.1', URI(@server.url).port])
      original.call(host, port, nil, options.merge(cert_store: store, open_timeout: 2, read_timeout: 2))
    end
  end

  def closed_connection
    Timeout.timeout(5) { @server.closed_connections.pop }
  end

  def expect_signed_requests
    @server.requests.each do |_, method, path, headers, body|
      signed_data = headers.fetch('access-timestamp') + method + path + body
      expect(headers.fetch('access-key')).to eq('key')
      expect(headers.fetch('access-sign')).to eq(OpenSSL::HMAC.hexdigest('sha256', 'secret', signed_data))
    end
  end
end
