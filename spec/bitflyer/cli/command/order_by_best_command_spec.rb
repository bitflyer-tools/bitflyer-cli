require 'spec_helper'

describe OrderByBestCommand do
  let!(:public_client) { stub_public_client }
  let!(:private_client) { stub_private_client }
  let(:response) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(public_client, ticker: { 'best_bid' => 1_000_000, 'best_ask' => 1_000_100 })
    stub_responses(private_client, send_child_order: response)
  end

  def run(type)
    described_class.new.run(thor_options(amount: 0.01, type: type))
  end

  it 'places a buy limit order at the best bid' do
    expect { run('buy') }.to output("An order is created buy / 1000000 / 0.01\n").to_stdout
    expect(private_client).to have_received(:send_child_order)
      .with(product_code: 'FX_BTC_JPY', child_order_type: 'LIMIT', side: 'BUY', price: 1_000_000, size: 0.01)
  end

  it 'places a sell limit order at the best ask' do
    expect { run('sell') }.to output(/sell \/ 1000100/).to_stdout
    expect(private_client).to have_received(:send_child_order).with(hash_including(side: 'SELL', price: 1_000_100))
  end

  it 'reads the FX_BTC_JPY ticker' do
    expect { run('buy') }.to output.to_stdout
    expect(public_client).to have_received(:ticker).with(product_code: 'FX_BTC_JPY')
  end

  context 'when the order is rejected' do
    let(:response) { { 'status' => -200 } }

    it 'prints the error response' do
      expect { run('buy') }.to output(/An error has occurred/).to_stdout
    end
  end
end
