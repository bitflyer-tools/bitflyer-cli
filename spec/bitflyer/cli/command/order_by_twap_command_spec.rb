require 'spec_helper'

describe OrderByTWAPCommand do
  let!(:private_client) { stub_private_client }
  let(:command) { described_class.new }
  let(:response) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(private_client, send_child_order: response)
    allow(command).to receive(:sleep)
  end

  def run
    command.run(thor_options(amount: 0.01, type: 'buy', number_of_times: 3, interval: 10))
  end

  it 'sends the given number of market orders' do
    expect { run }.to output.to_stdout
    expect(private_client).to have_received(:send_child_order)
      .with(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY', size: 0.01).exactly(3).times
  end

  it 'waits the interval after each order' do
    expect { run }.to output.to_stdout
    expect(command).to have_received(:sleep).with(10).exactly(3).times
  end

  context 'when an order is rejected' do
    let(:response) { { 'status' => -200 } }

    it 'prints the error response' do
      expect { run }.to output(/An error has occurred/).to_stdout
    end
  end
end
