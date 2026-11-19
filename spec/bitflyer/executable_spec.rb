require 'spec_helper'

describe 'bitflyer executable' do
  let(:private_client) { stub_private_client }

  def run_cancel_all
    stub_const('ARGV', ['cancel_all'])
    load File.expand_path('../../exe/bitflyer', __dir__)
  end

  it 'prints a cancel-all rejection to stderr and exits unsuccessfully' do
    stub_responses(private_client, cancel_all_child_orders: { 'status' => -200, 'error_message' => 'rejected' })

    expect do
      expect { run_cancel_all }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("rejected\n").to_stderr
  end

  it 'completes normally when the cancellation is accepted' do
    stub_responses(private_client, cancel_all_child_orders: '')

    expect { run_cancel_all }.to output('').to_stderr
    expect(Bitflyer).to have_received(:http_private_client).with('key', 'secret')
    expect(private_client).to have_received(:cancel_all_child_orders)
  end

  [
    %w[BITFLYER_API_KEY],
    %w[BITFLYER_API_SECRET],
    %w[BITFLYER_API_KEY BITFLYER_API_SECRET]
  ].each do |missing|
    it "exits before constructing a private client if missing #{missing.join(' and ')}" do
      stub_responses(private_client, cancel_all_child_orders: '')
      missing.each { |name| allow(ENV).to receive(:fetch).with(name, nil).and_return(nil) }

      expect do
        expect { run_cancel_all }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output('').to_stdout.and output("Set the required environment variables: #{missing.join(', ')}\n").to_stderr
      expect(Bitflyer).not_to have_received(:http_private_client)
      expect(private_client).not_to have_received(:cancel_all_child_orders)
    end
  end
end
