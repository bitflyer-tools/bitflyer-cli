require 'spec_helper'
require 'open3'

describe 'bitflyer executable' do
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
    positions = [position(side: 'BUY', price: 1_000_000, size: 0.2)]
    stub_responses(private_client, positions: positions, parent_orders: { 'status' => -200 }, send_parent_order: {})

    expect do
      expect { run_cli('stop_by_range', '--range=5000') }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/Failed to look up active parent orders:.*-200/).to_stderr
    expect(private_client).not_to have_received(:send_parent_order)
  end

  {
    %w[counter_trade] => "Your net position is already flat.\n",
    %w[stop_by_range --range=5000] => "You don't have any position now.\n"
  }.each do |args, flat_message|
    context "when #{args.first} reads positions" do
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

  ['<html>Bad Gateway</html>', ''].each do |body|
    it "reports an HTTP 502 with #{body.empty? ? 'an empty body' : 'an HTML body'} as unverified" do
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

  context 'with the SDK executions client' do
    before do
      stub_credentials
      transport = instance_double(Net::HTTP, request: response)
      allow(Net::HTTP).to receive(:start).with('api.bitflyer.jp', 443, use_ssl: true).and_yield(transport)
    end

    context 'when the HTTP 503 response has no body' do
      let(:response) { instance_double(Net::HTTPServiceUnavailable, body: nil) }

      it 'prints a lookup diagnostic without a table and exits with status 1' do
        expect do
          expect { run_cli('executions') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output(/\ACould not list executions\.[^\n]*\n\z/).to_stderr.and output('').to_stdout
      end
    end

    context 'when the HTTP 200 response contains an empty array' do
      let(:response) { instance_double(Net::HTTPOK, body: '[]') }

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

  {
    %w[counter_trade] => 'child',
    %w[order_by_best --amount=0.01 --type=buy] => 'child',
    %w[stop_by_range --range=5000] => 'parent',
    %w[ifdoco_by_range --amount=0.01 --type=buy --range=10000 --percentage=60] => 'parent'
  }.each do |args, order_type|
    context "when running #{args.first}" do
      let(:order_method) { :"send_#{order_type}_order" }

      before do
        positions = [position(side: 'BUY', price: 1_000_000, size: 0.1)]
        stub_responses(private_client, positions: positions, parent_orders: [])
        stub_responses(stub_public_client, ticker: { 'best_bid' => 1_000_000, 'ltp' => 1_000_000 })
      end

      it 'prints the exchange rejection to stderr and exits unsuccessfully' do
        stub_responses(private_client, order_method => { 'status' => -205, 'error_message' => 'Insufficient margin' })

        expect do
          expect { run_cli(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Insufficient margin\n").to_stderr.and output('').to_stdout
      end

      it 'completes normally when the order is accepted' do
        stub_responses(private_client, order_method => { "#{order_type}_order_acceptance_id" => 'accepted' })

        expect { run_cli(*args) }.to output('').to_stderr.and output(/.+/).to_stdout
        expect(private_client).to have_received(order_method)
      end
    end
  end
end
