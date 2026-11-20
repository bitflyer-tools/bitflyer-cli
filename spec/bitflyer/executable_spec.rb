require 'spec_helper'

describe 'bitflyer executable' do
  let(:private_client) { stub_private_client }

  def run_cli(*args)
    stub_const('ARGV', args)
    load File.expand_path('../../exe/bitflyer', __dir__)
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
end
