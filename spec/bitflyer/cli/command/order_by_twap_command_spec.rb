require 'spec_helper'

describe OrderByTWAPCommand do
  let!(:private_client) { stub_private_client }
  let(:command) { described_class.new }
  let(:response) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }
  let(:number_of_times) { 3 }

  before do
    stub_responses(private_client, send_child_order: response)
    allow(command).to receive(:sleep)
  end

  def run
    command.run(thor_options(amount: 0.01, type: 'buy', number_of_times: number_of_times, interval: 10))
  end

  it 'sends the given number of market orders' do
    expect { run }.to output.to_stdout
    expect(private_client).to have_received(:send_child_order)
      .with(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY', size: 0.01).exactly(3).times
  end

  it 'waits the interval only between orders' do
    events = []
    allow(private_client).to receive(:send_child_order) do
      events << :order
      response
    end
    allow(command).to receive(:sleep) { |interval| events << interval }

    expect { run }.to output.to_stdout
    expect(events).to eq([:order, 10, :order, 10, :order])
  end

  context 'when submitting a single order' do
    let(:number_of_times) { 1 }

    it 'prints the response without waiting' do
      expect { run }.to output(/#{response.fetch('child_order_acceptance_id')}/).to_stdout
      expect(private_client).to have_received(:send_child_order).once
      expect(command).not_to have_received(:sleep)
    end
  end

  context 'when an order is rejected' do
    let(:response) { { 'status' => -200 } }

    it 'prints the error response' do
      expect { run }.to output(/An error has occurred/).to_stdout
    end
  end
end
