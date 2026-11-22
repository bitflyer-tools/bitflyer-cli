require 'spec_helper'

describe OrderByBestCommand do
  let!(:public_client) { stub_public_client }
  let!(:private_client) { stub_private_client }
  let(:response) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(public_client, ticker: { 'best_bid' => 1_000_000, 'best_ask' => 1_000_100 })
    stub_responses(private_client, send_child_order: response)
  end

  def run(type, amount: 0.01)
    described_class.new.run(thor_options(amount: amount, type: type))
  end

  [Float::INFINITY, -Float::INFINITY, Float::NAN].each do |amount|
    it "rejects a non-finite amount of #{amount}" do
      expect { run('buy', amount: amount) }.to raise_error(Thor::Error, 'Amount must be positive and finite.')
      expect(public_client).not_to have_received(:ticker)
      expect(private_client).not_to have_received(:send_child_order)
    end
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

  it 'places an uppercase BUY limit order at the best bid' do
    expect { run('BUY') }.to output.to_stdout
    expect(private_client).to have_received(:send_child_order).with(hash_including(side: 'BUY', price: 1_000_000))
  end

  it 'places an uppercase SELL limit order at the best ask' do
    expect { run('SELL') }.to output.to_stdout
    expect(private_client).to have_received(:send_child_order).with(hash_including(side: 'SELL', price: 1_000_100))
  end

  it 'rejects an invalid side before reading the ticker or submitting an order' do
    expect { run('hold') }.to raise_error(Thor::Error, 'Order type must be buy or sell')
    expect(public_client).not_to have_received(:ticker)
    expect(private_client).not_to have_received(:send_child_order)
  end

  it 'reads the FX_BTC_JPY ticker' do
    expect { run('buy') }.to output.to_stdout
    expect(public_client).to have_received(:ticker).with(product_code: 'FX_BTC_JPY')
  end

  it 'reports a ticker rejection before submitting a limit order' do
    stub_responses(public_client, ticker: {
                     'status' => -1, 'error_message' => 'Ticker unavailable', 'best_bid' => 1_000_000
                   })

    expect { run('buy') }.to raise_error(HasHTTPClient::TickerError, 'Ticker error: Ticker unavailable')
    expect(private_client).not_to have_received(:send_child_order)
  end

  { 'buy' => 'best_bid', 'sell' => 'best_ask' }.each do |side, field|
    it "requires #{field} for a #{side} limit order" do
      ticker = { 'best_bid' => 1_000_000, 'best_ask' => 1_000_100 }
      ticker.delete(field)
      stub_responses(public_client, ticker: ticker)

      expect { run(side) }.to raise_error(HasHTTPClient::TickerError, /Ticker error: #{field}/)
      expect(private_client).not_to have_received(:send_child_order)
    end
  end

  context 'when the order is rejected' do
    let(:response) { { 'status' => -200 } }

    it 'raises with the exchange rejection' do
      expect { run('buy') }.to raise_error(Bitflyer::Cli::OrderRejected, /Order rejected:.*-200/)
    end
  end

  context 'when an acceptance ID accompanies a negative status' do
    let(:response) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001', 'status' => -200 } }

    it 'raises an unverified acceptance error' do
      expect { run('buy') }.to raise_error(Bitflyer::Cli::OrderRejected::Unverified)
    end
  end
end
