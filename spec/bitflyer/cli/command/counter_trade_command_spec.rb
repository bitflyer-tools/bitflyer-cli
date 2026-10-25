require 'spec_helper'

describe CounterTradeCommand do
  let!(:private_client) { stub_private_client }
  let(:accepted) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(private_client, positions: positions, send_child_order: accepted)
  end

  context 'with a long position' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.1), position(side: 'BUY', price: 1_000_000, size: 0.2)]
    end

    it 'sells the whole position at market' do
      expect { described_class.new.run }.to output("Clear position SELL / 0.3\n").to_stdout
      expect(private_client).to have_received(:send_child_order)
        .with(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'SELL', size: 0.3)
    end
  end

  context 'with a short position' do
    let(:positions) { [position(side: 'SELL', price: 1_000_000, size: 0.5)] }

    it 'buys the whole position at market' do
      expect { described_class.new.run }.to output("Clear position BUY / 0.5\n").to_stdout
      expect(private_client).to have_received(:send_child_order).with(hash_including(side: 'BUY', size: 0.5))
    end
  end

  context 'when the order is rejected' do
    let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.1)] }
    let(:accepted) { { 'status' => -205 } }

    it 'prints the error response' do
      expect { described_class.new.run }.to output(/An error has occurred/).to_stdout
    end
  end
end
