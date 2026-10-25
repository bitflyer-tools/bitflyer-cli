require 'spec_helper'

describe StopByRangeCommand do
  let!(:private_client) { stub_private_client }
  let(:response) { { 'parent_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(private_client, positions: positions, send_parent_order: response)
  end

  def run
    described_class.new.run(thor_options(range: 5000))
  end

  def stop_order(side:, trigger_price:, size:)
    {
      order_method: 'SIMPLE',
      parameters: [{ product_code: 'FX_BTC_JPY', condition_type: 'STOP', side: side, trigger_price: trigger_price,
                     size: size }]
    }
  end

  context 'without any position' do
    let(:positions) { [] }

    it 'does not send an order' do
      expect { run }.to output("You don't have any position now.\n").to_stdout
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end

  context 'with a long position' do
    let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.2)] }

    it 'sets a sell stop below the average price' do
      expect { run }.to output("Set stop order SELL / 995000.0 / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_parent_order)
        .with(stop_order(side: 'SELL', trigger_price: 995_000.0, size: 0.2))
    end
  end

  context 'with a short position' do
    let(:positions) { [position(side: 'SELL', price: 1_000_000, size: 0.2)] }

    it 'sets a buy stop above the average price' do
      expect { run }.to output("Set stop order BUY / 1005000.0 / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_parent_order)
        .with(stop_order(side: 'BUY', trigger_price: 1_005_000.0, size: 0.2))
    end
  end
end
