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

    it 'escapes terminal controls in the conflicting stop ID and exits without submitting an order' do
      stop = { 'parent_order_id' => "JCO\r\n\e[2J", 'parent_order_type' => 'STOP', 'side' => 'SELL', 'size' => 0.2 }
      stub_responses(private_client, parent_orders: [stop])

      expect do
        expect { run_cli('counter_trade') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Active protective stop (JCO\\r\\n\\e[2J) conflicts with the counter trade.\n").to_stderr
      expect(private_client).not_to have_received(:send_child_order)
    end

    it 'escapes terminal controls in the parent order ID for an unverifiable active order' do
      stop = { 'parent_order_id' => "JCO\r\n\e[2J", 'parent_order_type' => 'STOP', 'side' => nil, 'size' => 0.2 }
      stub_responses(private_client, parent_orders: [stop])

      expect do
        expect { run_cli('counter_trade') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not verify active parent order (JCO\\r\\n\\e[2J).\n").to_stderr
      expect(private_client).not_to have_received(:send_child_order)
    end
  end

  context 'when checking active stops before placing a protective stop' do
    let(:private_client) { stub_persistent_client }

    before do
      positions = [position(side: 'BUY', price: 1_000_000, size: 0.2)]
      stub_responses(private_client, positions: positions, send_parent_order: nil)
    end

    it 'escapes terminal controls in an existing stop order ID' do
      stop = { 'parent_order_id' => "JCO\r\n\e[2J", 'parent_order_type' => 'STOP', 'side' => 'SELL', 'size' => 0.2 }
      stub_responses(private_client, parent_orders: [stop])
      detail = { 'order_method' => 'SIMPLE',
                 'parameters' => [{ 'product_code' => 'FX_BTC_JPY', 'condition_type' => 'STOP', 'side' => 'SELL',
                                    'trigger_price' => 995_000, 'size' => 0.2 }] }
      allow(private_client).to receive(:parent_order).and_return(detail)

      expect { run_cli('stop_by_range', '--range=5000') }
        .to output("Existing stop order SELL / 995000.0 / 0.2 (JCO\\r\\n\\e[2J)\n").to_stdout
      expect(private_client).not_to have_received(:send_parent_order)
    end

    it 'escapes terminal controls in conflicting stop order IDs and exits without submitting an order' do
      stop = { 'parent_order_id' => "JCO\r\n\e[2J", 'parent_order_type' => 'STOP', 'side' => 'SELL', 'size' => 0.05 }
      stub_responses(private_client, parent_orders: [stop])

      expect do
        expect { run_cli('stop_by_range', '--range=5000') }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Conflicting active stop orders: JCO\\r\\n\\e[2J\n").to_stderr
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end

  {
    %w[counter_trade] => "Your net position is already flat.\n",
    %w[stop_by_range --range=5000] => "You don't have any position now.\n"
  }.each do |args, flat_message|
    context "when #{args.first} reads positions" do
      let(:private_client) { stub_persistent_client }

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
    private_client = stub_persistent_client
    allow(private_client).to receive(:ticker).and_return('status' => -1, 'error_message' => 'Ticker unavailable')
    allow(private_client).to receive(:send_child_order)

    expect do
      expect { run_cli('order_by_best', '--amount=0.01', '--type=buy') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Ticker error: Ticker unavailable\n").to_stderr
    expect(private_client).not_to have_received(:send_child_order)
  end

  it 'escapes terminal controls in the ticker rejection diagnostic on stderr' do
    private_client = stub_persistent_client
    allow(private_client).to receive(:ticker).and_return('status' => -1, 'error_message' => "Denied\r\n\e[2J")
    allow(private_client).to receive(:send_child_order)

    expect do
      expect { run_cli('order_by_best', '--amount=0.01', '--type=buy') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Ticker error: Denied\\r\\n\\e[2J\n").to_stderr.and output('').to_stdout
    expect(private_client).not_to have_received(:send_child_order)
  end

  it 'prints a cancel-all rejection to stderr and exits unsuccessfully' do
    stub_credentials
    stub_cancellation_response('400', JSON.generate(status: -200, error_message: 'rejected'))

    expect do
      expect { run_cli('cancel_all') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("rejected\n").to_stderr
  end

  it 'escapes terminal controls in the cancel-all rejection diagnostic on stderr' do
    stub_credentials
    stub_cancellation_response('400', JSON.generate(status: -200, error_message: "Denied\r\n\e[2J"))

    expect do
      expect { run_cli('cancel_all') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Denied\\r\\n\\e[2J\n").to_stderr.and output('').to_stdout
  end

  it 'escapes terminal controls in the cancel-order rejection diagnostic on stderr' do
    stub_credentials
    stub_cancellation_response('400', JSON.generate(status: -200, error_message: "Denied\r\n\e[2J"))

    expect do
      expect { run_cli('cancel_order', 'child', 'JOR-order') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Denied\\r\\n\\e[2J\n").to_stderr.and output('').to_stdout
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

  it 'exits before constructing the persistent private client when credentials are missing' do
    stub_credentials
    allow(ENV).to receive(:fetch).with('BITFLYER_API_KEY', nil).and_return(nil)
    expect(Bitflyer::Cli::PersistentHTTPClient).not_to receive(:new)

    expect do
      expect { run_cli('open_orders') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Set the required environment variables: BITFLYER_API_KEY\n").to_stderr
  end

  it 'routes open_orders through the CLI' do
    stub_responses(stub_persistent_client, child_orders: [], parent_orders: [])

    expect { run_cli('open_orders') }.to output("Child orders\nNone.\nParent strategies\nNone.\n").to_stdout
  end

  %w[child parent].each do |type|
    it "reports a read timeout while listing #{type} orders without printing a table" do
      client = stub_persistent_client
      stub_responses(client, child_orders: [], parent_orders: [])
      allow(client).to receive(:"#{type}_orders").and_raise(Net::ReadTimeout)

      expect do
        expect { run_cli('open_orders') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not list #{type} orders. Net::ReadTimeout\n").to_stderr.and output('').to_stdout
    end

    {
      'a non-object record' => nil,
      'a missing order ID' => {},
      'a blank order ID' => { "#{type}_order_id" => ' ' },
      'a non-string order ID' => { "#{type}_order_id" => 123 }
    }.each do |description, record|
      it "rejects #{description} in the #{type} orders response without printing rows" do
        responses = { child_orders: [{ 'child_order_id' => 'JOR-order' }], parent_orders: [] }
        stub_responses(stub_persistent_client, **responses.merge(:"#{type}_orders" => [record]))

        expect do
          expect { run_cli('open_orders') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output('').to_stdout.and output("Could not list #{type} orders. Unexpected response from bitFlyer.\n").to_stderr
      end
    end
  end

  it 'routes executions with a TWAP acceptance ID through the CLI' do
    private_client = stub_persistent_client
    stub_responses(private_client, executions: [])

    expect { run_cli('executions', '--child-order-acceptance-id', 'JRF-accepted') }
      .to output("No executions found.\n").to_stdout
    expect(private_client).to have_received(:executions)
      .with(product_code: 'FX_BTC_JPY', count: 100, child_order_acceptance_id: 'JRF-accepted').once
  end

  it 'prints an execution lookup rejection to stderr and exits unsuccessfully' do
    private_client = stub_persistent_client
    stub_responses(private_client, executions: { 'status' => -1, 'error_message' => 'Permission denied' })

    expect do
      expect { run_cli('executions') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not list executions. Permission denied\n").to_stderr
  end

  { 'open_orders' => [:child_orders, 'child orders'], 'executions' => [:executions, 'executions'] }.each do
    |command, (lookup, label)|
    it "escapes terminal controls in the #{command} diagnostic on stderr" do
      client = stub_persistent_client
      stub_responses(client, lookup => { 'status' => -1, 'error_message' => "Denied\r\n\e[2J" })

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
        private_client = stub_persistent_client
        stub_responses(private_client, executions: [fill, incomplete_fill])

        expect do
          expect { run_cli('executions') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Could not list executions. Unexpected response from bitFlyer.\n").to_stderr.and output('').to_stdout
      end
    end
  end

  context 'with the authenticated HTTP client' do
    let(:transport) { instance_double(Net::HTTP, started?: true, finish: nil) }

    before do
      stub_credentials
      allow(Net::HTTP).to receive(:start).with('api.bitflyer.jp', 443, use_ssl: true, keep_alive_timeout: 30)
                                        .and_return(transport)
      allow(transport).to receive(:request).and_return(listing_response('200', '[]'))
    end

    {
      '/v1/me/getchildorders' => ['open_orders', 'child orders'],
      '/v1/me/getparentorders' => ['open_orders', 'parent orders'],
      '/v1/me/getexecutions' => ['executions', 'executions']
    }.each do |path, (command, label)|
      it "reports the failed #{label} lookup when HTTP 503 contains an empty array" do
        allow(transport).to receive(:request).with(an_object_having_attributes(path: %r{^#{path}\?}))
                                             .and_return(listing_response('503', '[]'))

        expect do
          expect { run_cli(command) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Could not list #{label}. HTTP request failed (status 503)\n").to_stderr.and output('').to_stdout
        expect(transport).to have_received(:finish).once
      end
    end

    {
      'open_orders' => "Child orders\nNone.\nParent strategies\nNone.\n",
      'executions' => "No executions found.\n"
    }.each do |command, results|
      it "prints the empty #{command} results for HTTP 200" do
        expect { run_cli(command) }.to output(results).to_stdout.and output('').to_stderr
        expect(transport).to have_received(:finish).once
      end
    end

    it 'reports a bodyless HTTP 503 for executions without a table' do
      allow(transport).to receive(:request).and_return(listing_response('503', nil))

      expect do
        expect { run_cli('executions') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/\ACould not list executions\.[^\n]*\n\z/).to_stderr.and output('').to_stdout
    end

    it 'preserves the escaped exchange error detail for rejected lookups' do
      body = JSON.generate(status: -1, error_message: "Permission denied\n")
      allow(transport).to receive(:request).and_return(listing_response('403', body))

      expect do
        expect { run_cli('executions') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output("Could not list executions. Permission denied\\n\n").to_stderr.and output('').to_stdout
    end

    def listing_response(code, body)
      instance_double(Net::HTTPResponse, code: code, body: body)
    end
  end

  def stub_cancellation_response(code, body)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    transport = instance_double(Net::HTTP, request: response, started?: true, finish: nil)
    allow(Net::HTTP).to receive(:start).with('api.bitflyer.jp', 443, use_ssl: true, keep_alive_timeout: 30)
                                      .and_return(transport)
    transport
  end

  [
    ['200', '', nil, nil],
    ['400', '{"status":-200}', 'Cancel-all request rejected (status -200)',
     'Cancellation request rejected (status -200).'],
    ['400', '{"status":-200,"error_message":"Order is inactive."}', 'Order is inactive.',
     'Order is inactive.'],
    ['400', '{"error_message":"unexpected reply"}', 'Could not verify cancel-all acceptance from bitFlyer (HTTP 400).',
     'Could not verify cancellation acceptance from bitFlyer (HTTP 400).'],
    ['400', '{"status":-200.0,"error_message":"unexpected reply"}',
     'Could not verify cancel-all acceptance from bitFlyer (HTTP 400).',
     'Could not verify cancellation acceptance from bitFlyer (HTTP 400).'],
    ['408', '{"status":-200}', 'Could not verify cancel-all acceptance from bitFlyer (HTTP 408).',
     'Could not verify cancellation acceptance from bitFlyer (HTTP 408).'],
    ['503', '{"status":-200,"error_message":"Service unavailable."}',
     'Could not verify cancel-all acceptance from bitFlyer (HTTP 503).',
     'Could not verify cancellation acceptance from bitFlyer (HTTP 503).']
  ].each do |code, body, cancel_all_error, cancel_order_error|
    { %w[cancel_all] => cancel_all_error, %w[cancel_order child JOR-test] => cancel_order_error }.each do |args, error|
      it "classifies HTTP #{code} with #{body.inspect} for #{args.first}" do
        stub_credentials
        transport = stub_cancellation_response(code, body)

        if error
          expect do
            expect { run_cli(*args) }.to raise_error(SystemExit) { |exit| expect(exit.status).to eq(1) }
          end.to output("#{error}\n").to_stderr.and output('').to_stdout
        else
          success = args.first == 'cancel_all' ? '' : "Cancellation request accepted for child order JOR-test.\n"
          expect { run_cli(*args) }.to output(success).to_stdout.and output('').to_stderr
        end

        expect(transport).to have_received(:request).once
      end
    end
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
    end.to output("Order is no longer active.\n").to_stderr
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
      end.to output("Could not verify cancellation acceptance from bitFlyer (HTTP 400).\n").to_stderr
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
    end.to output("Could not verify cancellation acceptance from bitFlyer (HTTP 200).\n").to_stderr
  end

  it 'preserves a malformed counter trade record and exits before contacting bitFlyer' do
    stub_credentials
    path = File.join(Bitflyer::Cli::CounterTradeSubmission.state_directory, 'FX_BTC_JPY.json')
    malformed_record = '{"credential":'
    File.write(path, malformed_record)
    expect(Net::HTTP).not_to receive(:start)

    expect do
      expect { run_cli('counter_trade') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/Could not read the previous counter trade record\..*Record: #{Regexp.escape(path)}\n/m)
      .to_stderr.and output('').to_stdout
    expect(File.read(path)).to eq(malformed_record)
  end

  context 'when reconciling a counter trade through the CLI' do
    let(:transport) { instance_double(Net::HTTP, started?: false) }
    let(:acceptance_id) { 'JRF20180101-000000-000001' }

    before do
      stub_credentials
      stub_counter_trade_position(0.2)
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

    def stub_counter_trade_position(size)
      path = '/v1/me/getpositions?product_code=FX_BTC_JPY'
      positions = [position(side: 'BUY', price: 1_000_000, size: size)]
      allow(transport).to receive(:request).with(an_object_having_attributes(path: path))
                                          .and_return(order_response(200, positions))
    end

    def stub_order_lookup(response)
      path = "/v1/me/getchildorders?product_code=FX_BTC_JPY&child_order_acceptance_id=#{acceptance_id}"
      allow(transport).to receive(:request).with(an_object_having_attributes(path: path)).and_return(response)
    end

    it 'sizes the next offset from the exposure left by a terminal partial fill' do
      order = { 'child_order_acceptance_id' => acceptance_id, 'child_order_state' => 'CANCELED', 'executed_size' => 0.05 }
      stub_order_lookup(order_response(200, [order]))
      stub_counter_trade_position(0.15)

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

    it 'requires manual reconciliation when the order is absent from a successful empty lookup' do
      stub_order_lookup(order_response(200, []))

      expect do
        expect { run_cli('counter_trade') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/#{Regexp.escape(acceptance_id)}.*absent from the order history lookup.*Record:/m).to_stderr
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

    it 'retains the pending record when terminal history returns a bodyless 503' do
      stop = { product_code: 'FX_BTC_JPY', condition_type: 'STOP', side: 'SELL', trigger_price: 995_000.0, size: 0.1 }
      submission = Bitflyer::Cli::StopSubmission.new('key', stop)
      File.write(submission.path, 'accepted')
      unavailable = instance_double(Net::HTTPServiceUnavailable, code: '503', body: nil)
      canceled_history = an_object_having_attributes(path: %r{\A/v1/me/getparentorders\?.*parent_order_state=CANCELED})
      allow(transport).to receive(:request).with(canceled_history).and_return(unavailable)
      diagnostic = "Failed to look up terminal parent orders: Empty HTTP response body (status 503). " \
                   "Submission record: #{submission.path}\n"

      expect do
        expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(diagnostic).to_stderr.and output('').to_stdout
      expect(File.read(submission.path)).to eq('accepted')
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
    %w[stop_by_range --range=5000] => 'parent'
  }.each do |args, order_type|
    context "when #{args.first} cannot verify acceptance" do
      let(:private_client) { stub_persistent_client }
      let(:order_method) { :"send_#{order_type}_order" }

      before do
        positions = [position(side: 'BUY', price: 1_000_000, size: 0.1)]
        stub_responses(private_client, positions: positions, parent_orders: [])
      end

      {
        'a negative status' => ['accepted', { 'status' => -200 }],
        'an error message' => ['accepted', { 'error_message' => 'Insufficient margin' }],
        'a NUL-only ID' => ["\0", {}]
      }.each do |description, (acceptance_id, error_fields)|
        it "keeps acceptance unverified when the response includes #{description}" do
          body = error_fields.merge("#{order_type}_order_acceptance_id" => acceptance_id)
          response = Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, body)
          stub_responses(private_client, order_method => response)

          [/Could not verify .* acceptance \(HTTP 200\)/, /is unverified/].each do |diagnostic|
            expect do
              expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
            end.to output(diagnostic).to_stderr.and output('').to_stdout
          end
          expect(private_client).to have_received(order_method).once
        end
      end
    end
  end

  {
    %w[order_by_best --amount=0.01 --type=buy] => ['child', /An order is created buy/],
    %w[ifdoco_by_range --amount=0.01 --type=buy --range=10000 --percentage=60] => ['parent', /Send market order BUY/]
  }.each do |args, (order_type, confirmation)|
    context "when placing a single order with #{args.first}" do
      let(:transport) { instance_double(Net::HTTP, started?: true, finish: nil) }

      before do
        stub_credentials
        ticker_response = instance_double(Net::HTTPResponse, code: '200',
                                                               body: JSON.generate(best_bid: 1_000_000, ltp: 1_000_000))
        allow(transport).to receive(:request).with(instance_of(Net::HTTP::Get)).and_return(ticker_response)
        allow(Net::HTTP).to receive(:start).with('api.bitflyer.jp', 443, use_ssl: true, keep_alive_timeout: 30)
                                         .and_return(transport)
      end

      def stub_placement_response(status, body)
        response = instance_double(Net::HTTPResponse, code: status, body: body && JSON.generate(body))
        allow(transport).to receive(:request).with(instance_of(Net::HTTP::Post)).and_return(response)
      end

      def expect_single_submission(path)
        expect(transport).to have_received(:request).with(instance_of(Net::HTTP::Get)).once
        expect(transport).to have_received(:request).with(having_attributes(path: path)).once
      end

      it 'reports HTTP 503 with an acceptance ID as unverified without retrying' do
        stub_placement_response('503', "#{order_type}_order_acceptance_id" => 'accepted')

        expect do
          expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Could not verify order acceptance (HTTP 503).\n").to_stderr.and output('').to_stdout
        expect_single_submission("/v1/me/send#{order_type}order")
        expect(transport).to have_received(:finish).once
      end

      it 'reports a bodyless HTTP 503 as unverified without retrying' do
        stub_placement_response('503', nil)

        expect do
          expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output(/Could not verify order acceptance: .*status 503/).to_stderr.and output('').to_stdout
        expect_single_submission("/v1/me/send#{order_type}order")
      end

      it 'reports an explicit HTTP 400 exchange rejection' do
        stub_placement_response('400', 'status' => -205, 'error_message' => 'Insufficient margin')

        expect do
          expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Insufficient margin\n").to_stderr.and output('').to_stdout
        expect_single_submission("/v1/me/send#{order_type}order")
      end

      it 'escapes terminal controls in the order rejection diagnostic on stderr' do
        stub_placement_response('400', 'status' => -205, 'error_message' => "Denied\r\n\e[2J")

        expect do
          expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Denied\\r\\n\\e[2J\n").to_stderr.and output('').to_stdout
        expect_single_submission("/v1/me/send#{order_type}order")
      end

      it 'confirms placement for HTTP 201 with a valid acceptance ID' do
        stub_placement_response('201', "#{order_type}_order_acceptance_id" => 'accepted')

        expect { run_cli(*args) }.to output('').to_stderr.and output(confirmation).to_stdout
        expect_single_submission("/v1/me/send#{order_type}order")
        expect(transport).to have_received(:finish).once
      end
    end
  end

  {
    %w[counter_trade] => 'child',
    %w[order_by_best --amount=0.01 --type=buy] => 'child',
    %w[ifdoco_by_range --amount=0.01 --type=buy --range=10000 --percentage=60] => 'parent'
  }.each do |args, order_type|
    context "when running #{args.first}" do
      let(:order_method) { :"send_#{order_type}_order" }
      let(:private_client) { stub_persistent_client }

      def order_response(body)
        Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, body)
      end

      before do
        positions = [position(side: 'BUY', price: 1_000_000, size: 0.1)]
        stub_responses(private_client, positions: positions, parent_orders: [])
        allow(private_client).to receive(:ticker).and_return('best_bid' => 1_000_000, 'ltp' => 1_000_000)
      end

      it 'prints the exchange rejection to stderr and exits unsuccessfully' do
        stub_responses(private_client, order_method => order_response('status' => -205, 'error_message' => 'Insufficient margin'))

        expect do
          expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Insufficient margin\n").to_stderr.and output('').to_stdout
      end

      it 'completes normally when the order is accepted' do
        stub_responses(private_client, order_method => order_response("#{order_type}_order_acceptance_id" => 'accepted'))

        expect { run_cli(*args) }.to output('').to_stderr.and output(/.+/).to_stdout
        expect(private_client).to have_received(order_method)
      end

      unless args.first == 'counter_trade'
        ['', " \t\n", "\0", "\u3000", 123, true, false, nil].each do |acceptance_id|
          it "reports acceptance as unverified for ID #{acceptance_id.inspect} without retrying" do
            stub_responses(private_client, order_method => order_response("#{order_type}_order_acceptance_id" => acceptance_id))

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
