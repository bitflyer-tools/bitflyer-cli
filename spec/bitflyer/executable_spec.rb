require 'spec_helper'
require 'open3'

describe 'bitflyer executable', :stop_state, :counter_trade_state do
  let(:private_client) { stub_private_client }

  def run_bitflyer(*args)
    Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/bitflyer', *args, chdir: File.expand_path('../..', __dir__))
  end

  def run_cli(*args)
    stub_const('ARGV', args)
    load File.expand_path('../../exe/bitflyer', __dir__)
  end

  it 'exits unsuccessfully when a required option is missing' do
    _, stderr, status = run_bitflyer('order_by_best', '-a', '0.01')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to match(/required options.*--type/)
  end

  it 'exits unsuccessfully for a fractional TWAP order count' do
    _, stderr, status = run_bitflyer('order_by_twap', '-a', '0.01', '-t', 'buy', '-n', '1.9', '-i', '0')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('--number-of-times must be a positive whole number')
  end

  it 'exits successfully when displaying help' do
    stdout, stderr, status = run_bitflyer('help', 'order_by_best')

    expect(status).to be_success
    expect(stdout).to include('order_by_best')
    expect(stderr).to be_empty
  end

  it 'prints a protective stop lookup failure to stderr and exits unsuccessfully without placing an order' do
    private_client = stub_persistent_client
    positions = [position(side: 'BUY', price: 1_000_000, size: 0.2)]
    stub_responses(private_client, positions: positions, parent_orders: { 'status' => -200 }, send_parent_order: {})

    expect do
      expect { run_cli('stop_by_range', '--range=5000') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/Failed to look up active parent orders:.*-200/).to_stderr
    expect(private_client).not_to have_received(:send_parent_order)
  end

  context 'when checking protective stops before a counter trade' do
    let(:private_client) { stub_persistent_client }

    before do
      positions = [position(side: 'BUY', price: 1_000_000, size: 0.2)]
      stub_responses(private_client, positions: positions, send_child_order: nil)
    end

    it 'reports the conflicting stop ID and exits without submitting an order' do
      stop = { 'parent_order_id' => 'JCO-stop', 'parent_order_type' => 'STOP', 'side' => 'SELL', 'size' => 0.2 }
      stub_responses(private_client, parent_orders: [stop])

      expect do
        expect { run_cli('counter_trade') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/Active protective stop.*JCO-stop/).to_stderr
      expect(private_client).not_to have_received(:send_child_order)
    end

    it 'reports an unverifiable lookup and exits without submitting an order' do
      stub_responses(private_client, parent_orders: { 'status' => -200 })

      expect do
        expect { run_cli('counter_trade') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/Could not verify active protective stops.*-200/).to_stderr
      expect(private_client).not_to have_received(:send_child_order)
    end
  end

  {
    %w[counter_trade] => "Your net position is already flat.\n",
    %w[stop_by_range --range=5000] => "You don't have any position now.\n"
  }.each do |args, flat_message|
    context "when #{args.first} reads positions" do
      let(:private_client) { args.first == 'stop_by_range' ? stub_persistent_client : stub_private_client }

      before do
        stub_responses(private_client, positions: positions, send_child_order: {}, send_parent_order: {})
      end

      after do
        expect(private_client).not_to have_received(:send_child_order)
        expect(private_client).not_to have_received(:send_parent_order)
      end

      context 'with a rejected lookup' do
        let(:positions) { { 'status' => -200, 'error_message' => 'Invalid API key' } }

        it 'prints the API error to stderr and exits with status 1' do
          expect do
            expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          end.to output(/Failed to look up positions:.*-200.*Invalid API key/).to_stderr.and output('').to_stdout
        end
      end

      context 'with a malformed position row' do
        let(:positions) { [nil] }

        it 'prints the validation error to stderr and exits with status 1' do
          expect do
            expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          end.to output("Failed to look up positions: row 1: expected an object\n").to_stderr.and output('').to_stdout
        end
      end

      context 'with offsetting positions' do
        let(:positions) do
          [position(side: 'BUY', price: 1_000_000, size: 0.1), position(side: 'SELL', price: 1_100_000, size: 0.1)]
        end

        it 'completes normally without placing an order' do
          expect { run_cli(*args) }.to output('').to_stderr.and output(flat_message).to_stdout
        end
      end
    end
  end

  it 'prints a ticker rejection to stderr and exits unsuccessfully without placing an order' do
    public_client = stub_public_client
    stub_responses(public_client, ticker: { 'status' => -1, 'error_message' => 'Ticker unavailable' })
    stub_responses(private_client, send_child_order: {})

    expect do
      expect { run_cli('order_by_best', '--amount=0.01', '--type=buy') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Ticker error: Ticker unavailable\n").to_stderr
    expect(private_client).not_to have_received(:send_child_order)
  end

  it 'prints a cancel-all rejection to stderr and exits unsuccessfully' do
    stub_credentials
    stub_cancellation_response('400', JSON.generate(status: -200, error_message: 'rejected'))

    expect do
      expect { run_cli('cancel_all') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("rejected\n").to_stderr
  end

  it 'reports a malformed cancel-all response as unverified without retrying' do
    stub_credentials
    transport = stub_cancellation_response('200', 'Unexpected response')

    expect do
      expect { run_cli('cancel_all') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not verify cancel-all acceptance from bitFlyer (HTTP 200).\n").to_stderr
      .and output('').to_stdout
    expect(transport).to have_received(:request).once
  end

  it 'prints a limit order rejection to stderr and exits unsuccessfully' do
    stub_responses(stub_public_client, ticker: { 'best_bid' => 1_000_000 })
    stub_responses(private_client, send_child_order: { 'status' => -200, 'error_message' => 'Order rejected' })

    expect do
      expect { run_cli('order_by_best', '--amount=0.01', '--type=buy') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Order rejected\n").to_stderr
  end

  it 'completes normally when the cancellation is accepted' do
    stub_credentials
    transport = stub_cancellation_response('200', '')

    expect { run_cli('cancel_all') }.to output('').to_stderr
    expect(transport).to have_received(:request).once
  end

  [
    %w[BITFLYER_API_KEY],
    %w[BITFLYER_API_SECRET],
    %w[BITFLYER_API_KEY BITFLYER_API_SECRET]
  ].each do |missing|
    it "exits before constructing a private client if missing #{missing.join(' and ')}" do
      stub_credentials
      expect(CancellationClient).not_to receive(:new)
      missing.each { |name| allow(ENV).to receive(:fetch).with(name, nil).and_return(nil) }

      expect do
        expect { run_cli('cancel_all') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output('').to_stdout.and output("Set the required environment variables: #{missing.join(', ')}\n").to_stderr
    end
  end

  it 'exits before constructing a persistent private client when credentials are missing' do
    stub_credentials
    allow(ENV).to receive(:fetch).with('BITFLYER_API_KEY', nil).and_return(nil)
    expect(Bitflyer::Cli::PersistentHTTPClient).not_to receive(:new)

    expect do
      expect { run_cli('order_by_twap', '-a=0.01', '-t=buy', '-i=0', '-n=1') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Set the required environment variables: BITFLYER_API_KEY\n").to_stderr
  end

  it 'exits before starting the summary feed when credentials are missing' do
    stub_credentials
    allow(ENV).to receive(:fetch).with('BITFLYER_API_KEY', nil).and_return(nil)
    expect(Bitflyer::Cli::PersistentHTTPClient).not_to receive(:new)
    expect(Bitflyer::Cli::RealtimeClient).not_to receive(:new)

    expect do
      expect { run_cli('summary') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Set the required environment variables: BITFLYER_API_KEY\n").to_stderr.and output('').to_stdout
  end

  {
    positions: { 'status' => -200, 'error_message' => 'Invalid API key' },
    collateral: { 'status' => -1, 'collateral' => 60_000 }
  }.each do |lookup, response|
    it "exits with a diagnostic before starting the summary feed when #{lookup} is rejected" do
      client = stub_persistent_client
      stub_responses(client, **{ positions: [], collateral: { 'collateral' => 50_000 }, lookup => response })
      expect(Bitflyer::Cli::RealtimeClient).not_to receive(:new)

      expect do
        expect { run_cli('summary') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Failed to look up #{lookup}: #{response.inspect}\n").to_stderr.and output('').to_stdout
    end
  end

  it 'exits before starting the summary feed when a position row is malformed' do
    client = stub_persistent_client
    stub_responses(client, positions: [nil])
    expect(Bitflyer::Cli::RealtimeClient).not_to receive(:new)

    expect do
      expect { run_cli('summary') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Failed to look up positions: row 1: expected an object\n").to_stderr.and output('').to_stdout
  end

  it 'exits before sending a cancellation request when credentials are missing' do
    stub_credentials
    allow(ENV).to receive(:fetch).with('BITFLYER_API_SECRET', nil).and_return(nil)
    expect(CancellationClient).not_to receive(:new)

    expect do
      expect { run_cli('cancel_order', 'child', 'JOR-order') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Set the required environment variables: BITFLYER_API_SECRET\n").to_stderr
  end

  {
    'an HTML body' => '<html>Bad Gateway</html>',
    'an empty body' => '',
    'a negative-status JSON body' => JSON.generate(status: -1, error_message: 'Bad Gateway')
  }.each do |description, body|
    it "reports an HTTP 502 with #{description} as unverified" do
      stub_credentials
      stub_cancellation_response('502', body)

      expect do
        expect { run_cli('cancel_all') }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not verify cancel-all acceptance from bitFlyer (HTTP 502).\n").to_stderr
    end
  end

  it 'reports a cancel-all timeout as unverified without retrying' do
    stub_credentials
    transport = stub_cancellation_response('200', nil)
    allow(transport).to receive(:request).and_raise(Net::ReadTimeout)

    expect do
      expect { run_cli('cancel_all') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not verify cancel-all acceptance from bitFlyer.\n").to_stderr
    expect(transport).to have_received(:request).once
  end

  it 'exits before constructing an SDK private client when credentials are missing' do
    stub_credentials
    allow(ENV).to receive(:fetch).with('BITFLYER_API_KEY', nil).and_return(nil)
    expect(Bitflyer).not_to receive(:http_private_client)

    expect do
      expect { run_cli('open_orders') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Set the required environment variables: BITFLYER_API_KEY\n").to_stderr
  end

  it 'routes open_orders through the CLI' do
    stub_responses(private_client, child_orders: [], parent_orders: [])

    expect { run_cli('open_orders') }.to output("Child orders\nNone.\nParent strategies\nNone.\n").to_stdout
  end

  %w[child parent].each do |type|
    {
      'a non-object record' => nil,
      'a missing order ID' => {},
      'a blank order ID' => { "#{type}_order_id" => ' ' },
      'a non-string order ID' => { "#{type}_order_id" => 123 }
    }.each do |description, record|
      it "rejects #{description} in the #{type} orders response without printing rows" do
        responses = { child_orders: [{ 'child_order_id' => 'JOR-order' }], parent_orders: [] }
        stub_responses(private_client, **responses.merge(:"#{type}_orders" => [record]))

        expect do
          expect { run_cli('open_orders') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output('').to_stdout.and output("Could not list #{type} orders. Unexpected response from bitFlyer.\n").to_stderr
      end
    end
  end

  it 'routes executions with a TWAP acceptance ID through the CLI' do
    stub_responses(private_client, executions: [])

    expect { run_cli('executions', '--child-order-acceptance-id', 'JRF-accepted') }
      .to output("No executions found.\n").to_stdout
    expect(private_client).to have_received(:executions)
      .with(product_code: 'FX_BTC_JPY', count: 100, child_order_acceptance_id: 'JRF-accepted').once
  end

  it 'prints an execution lookup rejection to stderr and exits unsuccessfully' do
    stub_responses(private_client, executions: { 'status' => -1, 'error_message' => 'Permission denied' })

    expect do
      expect { run_cli('executions') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not list executions. Permission denied\n").to_stderr
  end

  { 'open_orders' => [:child_orders, 'child orders'], 'executions' => [:executions, 'executions'] }.each do
    |command, (lookup, label)|
    it "escapes terminal controls in the #{command} diagnostic on stderr" do
      stub_responses(private_client, lookup => { 'status' => -1, 'error_message' => "Denied\r\n\e[2J" })

      expect do
        expect { run_cli(command) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not list #{label}. Denied\\r\\n\\e[2J\n").to_stderr.and output('').to_stdout
    end
  end

  context 'when the executions page contains an incomplete fill' do
    let(:fill) do
      {
        'exec_date' => '2025-01-01T00:00:00.123', 'side' => 'SELL', 'price' => 30_000, 'size' => 0.01,
        'commission' => 0, 'child_order_id' => 'JOR-order', 'child_order_acceptance_id' => 'JRF-accepted'
      }
    end

    {
      'an empty object' => {},
      'a missing acceptance ID' => :missing,
      'a null acceptance ID' => nil,
      'a blank acceptance ID' => ' '
    }.each do |description, acceptance_id|
      it "exits with status 1 and no table for #{description}" do
        incomplete_fill = case acceptance_id
                          when Hash then acceptance_id
                          when :missing then fill.reject { |key| key == 'child_order_acceptance_id' }
                          else fill.merge('child_order_acceptance_id' => acceptance_id)
                          end
        stub_responses(private_client, executions: [fill, incomplete_fill])

        expect do
          expect { run_cli('executions') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Could not list executions. Unexpected response from bitFlyer.\n").to_stderr.and output('').to_stdout
      end
    end
  end

  context 'with the SDK executions client' do
    before do
      stub_credentials
      transport = instance_double(Net::HTTP, request: response)
      allow(Net::HTTP).to receive(:start).with('api.bitflyer.jp', 443, use_ssl: true).and_yield(transport)
    end

    context 'when the HTTP 503 response has no body' do
      let(:response) { instance_double(Net::HTTPServiceUnavailable, code: '503', body: nil) }

      it 'prints a lookup diagnostic without a table and exits with status 1' do
        expect do
          expect { run_cli('executions') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output(/\ACould not list executions\.[^\n]*\n\z/).to_stderr.and output('').to_stdout
      end
    end

    context 'when the HTTP 200 response contains an empty array' do
      let(:response) { instance_double(Net::HTTPOK, code: '200', body: '[]') }

      it 'prints the empty result and completes successfully' do
        expect { run_cli('executions') }.to output("No executions found.\n").to_stdout.and output('').to_stderr
      end
    end
  end

  def stub_cancellation_response(code, body)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    transport = instance_double(Net::HTTP, request: response)
    allow(Net::HTTP).to receive(:start).with('api.bitflyer.jp', 443, use_ssl: true).and_yield(transport)
    transport
  end

  def expect_cancellation_request(transport, type, id)
    expect(transport).to have_received(:request).once do |request|
      expect(request).to be_a(Net::HTTP::Post)
      expect(request.path).to eq("/v1/me/cancel#{type}order")
      expect(JSON.parse(request.body)).to eq('product_code' => 'FX_BTC_JPY', "#{type}_order_id" => id)
      expect(request['ACCESS-KEY']).to eq('key')
      signed_data = "#{request['ACCESS-TIMESTAMP']}POST#{request.path}#{request.body}"
      expect(request['ACCESS-SIGN']).to eq(OpenSSL::HMAC.hexdigest('SHA256', 'secret', signed_data))
    end
  end

  it 'requests cancellation of only the specified child order' do
    stub_credentials
    transport = stub_cancellation_response('200', '')

    expect { run_cli('cancel_order', 'child', 'JOR-order') }
      .to output("Cancellation request accepted for child order JOR-order.\n").to_stdout
    expect_cancellation_request(transport, 'child', 'JOR-order')
  end

  it 'requests parent cancellation when explicitly confirmed' do
    stub_credentials
    transport = stub_cancellation_response('200', nil)

    expect { run_cli('cancel_order', 'parent', 'JCO-order', '--confirm-parent') }
      .to output("Cancellation request accepted for parent order JCO-order.\n").to_stdout
    expect_cancellation_request(transport, 'parent', 'JCO-order')
  end

  it 'requires confirmation before contacting bitFlyer to cancel a parent strategy' do
    expect do
      expect { run_cli('cancel_order', 'parent', 'JCO-order') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/associated orders.*--confirm-parent/).to_stderr
  end

  it 'rejects an unknown order type before contacting bitFlyer' do
    expect do
      expect { run_cli('cancel_order', 'other', 'JOR-order') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/Order type must be child or parent/).to_stderr
  end

  it 'requires an order ID before contacting bitFlyer' do
    expect do
      expect { run_cli('cancel_order', 'child') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Order ID is required.\n").to_stderr
  end

  it 'reports a rejected cancellation on stderr and exits unsuccessfully' do
    stub_credentials
    stub_cancellation_response('400', JSON.generate(status: -200, error_message: 'Order is no longer active.'))

    expect do
      expect { run_cli('cancel_order', 'child', 'JOR-order') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Cancellation request rejected. Order is no longer active.\n").to_stderr
  end

  it 'reports the exchange status when a cancellation rejection has no message' do
    stub_credentials
    stub_cancellation_response('400', JSON.generate(status: -200))

    expect do
      expect { run_cli('cancel_order', 'child', 'JOR-order') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Cancellation request rejected (status -200).\n").to_stderr
  end

  [{}, '-200', -200.5].each do |status|
    it "reports a cancellation status of #{status.inspect} as unverified" do
      stub_credentials
      stub_cancellation_response('400', JSON.generate(status: status))

      expect do
        expect { run_cli('cancel_order', 'child', 'JOR-order') }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not verify cancellation acceptance from bitFlyer.\n").to_stderr
    end
  end

  it 'reports an empty HTTP 502 as unverified without printing acceptance' do
    stub_credentials
    stub_cancellation_response('502', '')

    expect do
      expect do
        expect { run_cli('cancel_order', 'child', 'JOR-order') }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not verify cancellation acceptance from bitFlyer (HTTP 502).\n").to_stderr
    end.to output('').to_stdout
  end

  it 'reports HTTP 503 as unverified even if the body contains an API error' do
    stub_credentials
    stub_cancellation_response('503', JSON.generate(status: -200, error_message: 'Service unavailable.'))

    expect do
      expect { run_cli('cancel_order', 'parent', 'JCO-order', '--confirm-parent') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not verify cancellation acceptance from bitFlyer (HTTP 503).\n").to_stderr
  end

  it 'reports a read timeout as unverified without retrying cancellation' do
    stub_credentials
    transport = stub_cancellation_response('200', nil)
    allow(transport).to receive(:request).and_raise(Net::ReadTimeout)

    expect do
      expect { run_cli('cancel_order', 'child', 'JOR-order') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not verify cancellation acceptance from bitFlyer.\n").to_stderr
    expect(transport).to have_received(:request).once
  end

  it 'reports when an unexpected response leaves acceptance unverified' do
    stub_credentials
    stub_cancellation_response('200', 'Unexpected response')

    expect do
      expect { run_cli('cancel_order', 'child', 'JOR-order') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not verify cancellation acceptance from bitFlyer.\n").to_stderr
  end

  context 'when reconciling a counter trade through the CLI' do
    let(:private_client) do
      stub_credentials
      instance_double(Bitflyer::HTTP::Private::Client).tap do |client|
        allow(Bitflyer).to receive(:http_private_client).with('key', 'secret').and_return(client)
      end
    end
    let(:transport) { instance_double(Net::HTTP, started?: false) }
    let(:acceptance_id) { 'JRF20180101-000000-000001' }

    before do
      allow(private_client).to receive(:positions).and_return([position(side: 'BUY', price: 1_000_000, size: 0.2)])
      allow(Net::HTTP).to receive(:start).with('api.bitflyer.jp', 443, use_ssl: true, keep_alive_timeout: 30)
                                       .and_return(transport)
      allow(transport).to receive(:request).with(an_object_having_attributes(path: %r{\A/v1/me/getparentorders\?}))
                                           .and_return(order_response(200, []))
      allow(transport).to receive(:request).with(an_object_having_attributes(path: '/v1/me/sendchildorder'))
                                          .and_return(order_response(200, 'child_order_acceptance_id' => acceptance_id))
      expect { run_cli('counter_trade') }.to output("Clear position SELL / 0.2\n").to_stdout
    end

    def order_response(status, body)
      instance_double(Net::HTTPResponse, code: status.to_s, body: JSON.generate(body))
    end

    def stub_order_lookup(response)
      path = "/v1/me/getchildorders?product_code=FX_BTC_JPY&child_order_acceptance_id=#{acceptance_id}"
      allow(transport).to receive(:request).with(an_object_having_attributes(path: path)).and_return(response)
    end

    it 'sizes the next offset from the exposure left by a terminal partial fill' do
      order = { 'child_order_acceptance_id' => acceptance_id, 'child_order_state' => 'CANCELED', 'executed_size' => 0.05 }
      stub_order_lookup(order_response(200, [order]))
      allow(private_client).to receive(:positions).and_return([position(side: 'BUY', price: 1_000_000, size: 0.15)])

      expect { run_cli('counter_trade') }.to output("Clear position SELL / 0.15\n").to_stdout
      expect(transport).to have_received(:request).with(
        an_object_having_attributes(path: '/v1/me/sendchildorder', body: a_string_including('"size":0.15'))
      )
    end

    it 'leaves the record in place when the order lookup fails' do
      stub_order_lookup(order_response(503, []))

      expect do
        expect { run_cli('counter_trade') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/awaiting reconciliation.*Record:/m).to_stderr
      expect(transport).to have_received(:request)
        .with(an_object_having_attributes(path: '/v1/me/sendchildorder')).once
    end
  end

  context 'when submitting a protective stop' do
    let(:args) { %w[stop_by_range --range=5000] }
    let(:transport) { instance_double(Net::HTTP, started?: false) }

    before do
      positions = [position(side: 'BUY', price: 1_000_000, size: 0.1)]
      stub_credentials
      allow(transport).to receive(:request).with(an_object_having_attributes(path: %r{\A/v1/me/getpositions\?}))
                                           .and_return(instance_double(Net::HTTPOK, code: '200', body: positions.to_json))
      allow(transport).to receive(:request).with(an_object_having_attributes(path: %r{\A/v1/me/getparentorders\?}))
                                           .and_return(instance_double(Net::HTTPOK, code: '200', body: '[]'))
      allow(Net::HTTP).to receive(:start).with('api.bitflyer.jp', 443, use_ssl: true, keep_alive_timeout: 30)
                                       .and_return(transport)
    end

    it 'prints a definitive exchange rejection to stderr and exits unsuccessfully' do
      response = instance_double(Net::HTTPBadRequest, code: '400',
                                  body: '{"status":-205,"error_message":"Insufficient margin"}')
      allow(transport).to receive(:request).with(parent_submission_request).and_return(response)

      expect do
        expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Insufficient margin\n").to_stderr.and output('').to_stdout
    end

    it 'reports successful acceptance' do
      response = instance_double(Net::HTTPOK, code: '200', body: '{"parent_order_acceptance_id":"accepted"}')
      allow(transport).to receive(:request).with(parent_submission_request).and_return(response)

      expect { run_cli(*args) }.to output(/Set stop order/).to_stdout.and output('').to_stderr
    end

    {
      'HTTP 503 with an exchange rejection body' => /HTTP 503/,
      'a read timeout' => /communication error/
    }.each do |failure, message|
      it "reports an unverified stop and exits unsuccessfully after #{failure} and on retry" do
        if failure == 'a read timeout'
          allow(transport).to receive(:request).with(parent_submission_request).and_raise(Net::ReadTimeout)
        else
          response = instance_double(Net::HTTPServiceUnavailable, code: '503', body: '{"status":-205}')
          allow(transport).to receive(:request).with(parent_submission_request).and_return(response)
        end

        [message, /unverified.*awaiting confirmation/].each do |diagnostic|
          expect do
            expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
          end.to output(/#{diagnostic}.*Check the order in bitFlyer before retrying.*record at:\n#{record_path}\n/m)
            .to_stderr.and output('').to_stdout
        end

        expect(transport).to have_received(:request).with(parent_submission_request).once
      end
    end

    it 'reports the pending record on a retry when the active order lookup returns a bodyless 503' do
      stop = { product_code: 'FX_BTC_JPY', condition_type: 'STOP', side: 'SELL', trigger_price: 995_000.0, size: 0.1 }
      submission = Bitflyer::Cli::StopSubmission.new('key', stop)
      File.write(submission.path, 'unverified')
      unavailable = instance_double(Net::HTTPServiceUnavailable, code: '503', body: nil)
      allow(transport).to receive(:request).with(an_object_having_attributes(path: %r{\A/v1/me/getparentorders\?}))
                                           .and_return(unavailable)
      diagnostic = "Failed to look up active parent orders: Empty HTTP response body (status 503).\n" \
                   "Check the order in bitFlyer before retrying. Once you confirm the outcome, " \
                   "remove the unverified submission record at:\n#{submission.path}\n"

      expect do
        expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(diagnostic).to_stderr.and output('').to_stdout
      expect(File.read(submission.path)).to eq('unverified')
      expect(transport).not_to have_received(:request).with(instance_of(Net::HTTP::Post))
    end

    def record_path
      %r{#{Regexp.escape(@stop_state_directory)}/[0-9a-f]{64}}
    end

    def parent_submission_request
      an_object_having_attributes(path: '/v1/me/sendparentorder')
    end
  end

  {
    %w[counter_trade] => 'child',
    %w[order_by_best --amount=0.01 --type=buy] => 'child',
    %w[ifdoco_by_range --amount=0.01 --type=buy --range=10000 --percentage=60] => 'parent'
  }.each do |args, order_type|
    context "when running #{args.first}" do
      let(:order_method) { :"send_#{order_type}_order" }
      let(:private_client) { args.first == 'counter_trade' ? stub_persistent_client : stub_private_client }

      def order_response(command, body)
        return body unless command == 'counter_trade'

        Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, body)
      end

      before do
        positions = [position(side: 'BUY', price: 1_000_000, size: 0.1)]
        stub_responses(private_client, positions: positions, parent_orders: [])
        stub_responses(stub_public_client, ticker: { 'best_bid' => 1_000_000, 'ltp' => 1_000_000 })
      end

      it 'prints the exchange rejection to stderr and exits unsuccessfully' do
        stub_responses(private_client, order_method => order_response(args.first, { 'status' => -205, 'error_message' => 'Insufficient margin' }))

        expect do
          expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Insufficient margin\n").to_stderr.and output('').to_stdout
      end

      it 'completes normally when the order is accepted' do
        stub_responses(private_client, order_method => order_response(args.first, { "#{order_type}_order_acceptance_id" => 'accepted' }))

        expect { run_cli(*args) }.to output('').to_stderr.and output(/.+/).to_stdout
        expect(private_client).to have_received(order_method)
      end

      unless args.first == 'counter_trade'
        ['', " \t\n", "\u3000", 123, true, false, nil].each do |acceptance_id|
          it "reports acceptance as unverified for ID #{acceptance_id.inspect} without retrying" do
            stub_responses(private_client, order_method => { "#{order_type}_order_acceptance_id" => acceptance_id })

            expect do
              expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
            end.to output("Could not verify order acceptance.\n").to_stderr.and output('').to_stdout
            expect(private_client).to have_received(order_method).once
          end
        end
      end
    end
  end
end
