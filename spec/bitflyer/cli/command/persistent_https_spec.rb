require 'spec_helper'

describe 'Persistent exchange HTTPS' do
  let(:order_path) { '/v1/me/sendchildorder' }
  let(:positions_path) { '/v1/me/getpositions?product_code=FX_BTC_JPY' }
  let(:active_parent_orders_path) { '/v1/me/getparentorders?product_code=FX_BTC_JPY&count=100&parent_order_state=ACTIVE' }
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

  {
    'an HTML gateway response' => ['<html>Bad Gateway</html>', '502 Bad Gateway'],
    'a gateway response with an exchange error body' => [{ 'status' => -200 }, '502 Bad Gateway'],
    'a gateway response with an acceptance ID' => [
      { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' }, '502 Bad Gateway'
    ],
    'a malformed success response' => ['[', '200 OK'],
    'an empty success response' => ['', '200 OK'],
    'a success response with only an error message' => [{ 'error_message' => 'Order unavailable' }, '200 OK'],
    'a success response with a blank acceptance ID' => [{ 'child_order_acceptance_id' => ' ' }, '200 OK'],
    'a success response with a NUL-only acceptance ID' => [{ 'child_order_acceptance_id' => "\0" }, '200 OK'],
    'a client error without an exchange rejection' => [{}, '400 Bad Request']
  }.each do |description, (body, status)|
    it "stops submitting and exits unsuccessfully after #{description}" do
      start_server { |_path, number| number == 2 ? [body, false, status] : [acceptance, false] }

      expect do
        expect do
          Bitflyer::Cli::Runner.start(%w[order_by_twap -a 0.01 -t buy -n 3 -i 0])
        end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/1 accepted, 0 rejected, 1 unverified, 1 unattempted\./).to_stdout

      expect(closed_connection).to eq(1)
      expect(@server.requests.map { |_, method, path| [method, path] }).to eq([['POST', order_path]] * 2)
    end
  end

  context 'when looking up a protective stop', :stop_state do
    let(:position_rows) { [position(side: 'BUY', price: 1_000_000, size: 0.1)] }
    let(:parent_orders) do
      %w[JCO-first JCO-second].map { |id| { parent_order_id: id, parent_order_type: 'STOP' } }
    end
    let(:stop_submission_path) { '/v1/me/sendparentorder' }
    let(:lookup_requests) do
      [
        [1, 'GET', positions_path],
        [1, 'GET', positions_path],
        [1, 'GET', active_parent_orders_path],
        [1, 'GET', '/v1/me/getparentorder?parent_order_id=JCO-first'],
        [1, 'GET', '/v1/me/getparentorder?parent_order_id=JCO-second']
      ]
    end
    let(:submission_requests) { lookup_requests + [[1, 'GET', positions_path], [1, 'POST', stop_submission_path]] }

    it 'checks positions and multiple candidates and submits on one TLS connection' do
      start_stop_server

      expect { run_stop }.to output(/Set stop order/).to_stdout

      expect_stop_requests(submission_requests)
      expect_signed_requests
    end

    it 'closes the connection without submitting when a matching stop exists' do
      start_stop_server(second_detail: stop_detail(995_000))

      expect { run_stop }.to output(/Existing stop order.*JCO-second/).to_stdout

      expect_stop_requests(lookup_requests)
    end

    it 'closes the connection without submitting when a detail lookup fails' do
      start_stop_server(second_detail: { status: -200 })

      expect { run_stop }.to raise_error(StopByRangeCommand::LookupFailed, /JCO-second/)

      expect_stop_requests(lookup_requests)
    end

    it 'does not replay a submission whose response is lost' do
      start_stop_server(submission: nil)

      expect { run_stop }.to raise_error(Bitflyer::Cli::StopSubmission::Unverified, /communication error/)

      expect_stop_requests(submission_requests)
    end

    def run_stop
      StopByRangeCommand.new.run(thor_options(range: 5000))
    end

    def stop_detail(trigger_price)
      {
        order_method: 'SIMPLE',
        parameters: [{ product_code: 'FX_BTC_JPY', condition_type: 'STOP', side: 'SELL', trigger_price: trigger_price,
                       size: 0.1 }]
      }
    end

    def start_stop_server(second_detail: stop_detail(990_000), submission: { parent_order_acceptance_id: 'accepted' })
      responses = [position_rows, position_rows, parent_orders, stop_detail(980_000), second_detail, position_rows,
                   submission]
      start_server { |_path, number| [responses.fetch(number - 1, submission), false] }
    end

    def expect_stop_requests(requests)
      expect(closed_connection).to eq(1)
      expect(@server.requests.map { |id, method, path| [id, method, path] }).to eq(requests)
    end
  end

  context 'when offsetting a position', :counter_trade_state do
    let(:position_rows) { [position(side: 'BUY', price: 1_000_000, size: 0.1)] }
    let(:acceptance_id) { acceptance.fetch('child_order_acceptance_id') }
    let(:previous_order_path) do
      "/v1/me/getchildorders?product_code=FX_BTC_JPY&child_order_acceptance_id=#{acceptance_id}"
    end
    let(:submission) { Bitflyer::Cli::CounterTradeSubmission.new('FX_BTC_JPY', 'key') }

    it 'reads the position, checks protective stops, and submits the offset on one TLS connection' do
      responses = { positions_path => position_rows, active_parent_orders_path => [], order_path => acceptance }
      start_server { |path| [responses.fetch(path), false] }

      expect { CounterTradeCommand.new.run }.to output("Clear position SELL / 0.1\n").to_stdout

      expect_counter_trade_requests([
        [1, 'GET', positions_path], [1, 'GET', active_parent_orders_path], [1, 'POST', order_path]
      ])
    end

    {
      '401 Unauthorized' => 'Invalid API key',
      '503 Service Unavailable' => 'Positions unavailable'
    }.each do |status, message|
      it "prints the position lookup error for HTTP #{status} and exits without trading" do
        body = { 'status' => -200, 'error_message' => message }
        start_server { [body, false, status] }
        stub_const('ARGV', %w[counter_trade])

        expect do
          expect { load File.expand_path('../../../../exe/bitflyer', __dir__) }
            .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Failed to look up positions: #{body.inspect}\n").to_stderr.and output('').to_stdout

        expect_counter_trade_requests([[1, 'GET', positions_path]])
        expect(submission.pending).to be_nil
      end
    end

    it 'looks up the previous fill and confirms the resulting exposure on one TLS connection' do
      start_reconciliation_server([])

      expect { CounterTradeCommand.new.run }.to output("You don't have any position now.\n").to_stdout

      expect_counter_trade_requests([[1, 'GET', previous_order_path], [1, 'GET', positions_path]])
      expect(submission.pending).to be_nil
    end

    it 'keeps the record and suppresses another order while exposure is stale' do
      start_reconciliation_server(position_rows)

      expect { CounterTradeCommand.new.run }.to raise_error(Thor::Error, /exposure is not confirmed/)

      expect_counter_trade_requests([[1, 'GET', previous_order_path], [1, 'GET', positions_path]])
      expect(submission.pending).to include('acceptance_id' => acceptance_id)
    end

    def start_reconciliation_server(positions)
      submission.record(BigDecimal('0.1'), acceptance_id)
      fill = acceptance.merge('child_order_state' => 'COMPLETED', 'executed_size' => 0.1)
      start_server { |path| [path == positions_path ? positions : [fill], false] }
    end

    def expect_counter_trade_requests(requests)
      expect(closed_connection).to eq(1)
      expect(@server.requests.map { |id, method, path| [id, method, path] }).to eq(requests)
      expect_signed_requests
    end
  end

  it 'uses one TLS connection for startup and multiple summary refreshes and closes it on interrupt' do
    start_server { |path| [path == positions_path ? [] : { collateral: 50_000 }, false] }
    feed = stub_realtime_client
    allow(feed).to receive(:disconnected=)
    allow(feed).to receive(:executions_fx_btc_jpy=)
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

  it 'renders the last complete snapshot as stale after a bodyless 503 and recovers on the next poll' do
    http = instance_double(Net::HTTP, started?: false)
    allow(Net::HTTP).to receive(:start).and_return(http)
    positions = [[position(side: 'BUY', price: 1_000_000, size: 0.1)],
                 [position(side: 'BUY', price: 1_000_000, size: 0.2)]]
    allow(http).to receive(:request).with(an_object_having_attributes(path: positions_path))
                                   .and_return(*positions.map { |rows| json_response(rows) })
    unavailable = instance_double(Net::HTTPServiceUnavailable, body: nil, code: '503')
    allow(http).to receive(:request).with(an_object_having_attributes(path: collateral_path))
                                   .and_return(json_response(collateral: 50_000), unavailable,
                                               json_response(collateral: 60_000))
    feed = stub_realtime_client
    allow(feed).to receive(:disconnected=)
    allow(feed).to receive(:executions_fx_btc_jpy=) { |callback| callback.call([{ 'price' => 1_000_000 }]) }

    command = SummaryCommand.new
    poller = nil
    allow(Thread).to receive(:new) do |&poll|
      poller = Fiber.new(&poll)
      poller.resume
      instance_double(Thread, kill: nil)
    end
    allow(command).to receive(:sleep).with(5) { Fiber.yield }
    expect(command).to receive(:sleep).with(0.1).exactly(3).times.and_invoke(
      ->(_) { poller.resume },
      ->(_) { poller.resume },
      ->(_) { raise Interrupt }
    )

    expect { command.run }.to output(satisfy do |output|
      initial, stale, recovered = output.split("\e[4F\e[0J").drop(1)
      expect(initial).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000')
      expect(initial).not_to include('[stale]')
      expect(stale).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000', '[stale]')
      expect(recovered).to include('Position: 1,000,000 * 0.2', 'Balance:  60,000')
      expect(recovered).not_to include('[stale]')
    end).to_stdout
  end

  def json_response(payload)
    instance_double(Net::HTTPOK, code: '200', body: JSON.generate(payload))
  end

  def run_twap(command, slices)
    command.run(thor_options(amount: 0.01, type: 'buy', number_of_times: slices, interval: 0))
  end

  def start_server(&reply)
    @server = KeepAliveHTTPSServer.new(&reply)
    store = OpenSSL::X509::Store.new
    store.add_cert(@server.certificate)
    stub_const('Bitflyer::HTTP::BASE_URL', @server.url)
    allow(Net::HTTP).to receive(:start).and_wrap_original do |original, host, port, **options, &session|
      expect([host, port]).to eq(['127.0.0.1', URI(@server.url).port])
      original.call(host, port, nil, options.merge(cert_store: store, open_timeout: 2, read_timeout: 2), &session)
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
