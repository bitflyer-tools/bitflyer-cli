require 'spec_helper'

describe StopByRangeCommand do
  let!(:private_client) { stub_private_client }
  let(:response) { { 'parent_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(private_client, positions: positions, send_parent_order: response)
  end

  def run(range = 5000)
    described_class.new.run(thor_options(range: range))
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

  context 'when the position lookup is rejected' do
    let(:positions) { { 'status' => -200 } }

    it 'reports the API status without constructing a position or sending an order' do
      expect(Position).not_to receive(:new)
      expect { run }.to output(/Failed to look up positions:.*-200/).to_stderr
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end

  context 'with a long position' do
    let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.2)] }

    [0, -5000].each do |range|
      it "rejects a range of #{range} without sending an order" do
        expect { run(range) }.to raise_error(ArgumentError, 'Range must be positive')
        expect(private_client).not_to have_received(:send_parent_order)
      end
    end

    it 'sets a sell stop below the average price' do
      expect { run }.to output("Set stop order SELL / 995000.0 / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_parent_order)
        .with(stop_order(side: 'SELL', trigger_price: 995_000.0, size: 0.2))
    end

    context 'when the stop order is rejected' do
      let(:response) { { 'status' => -200, 'error_message' => 'Order rejected' } }

      it 'prints the API error response' do
        expect { run }.to output("An error has occurred#{response}\n").to_stdout
      end
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

  context 'with a net long position' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.3), position(side: 'SELL', price: 1_100_000, size: 0.1)]
    end

    it 'sets a sell stop below the net entry price' do
      expect { run }.to output("Set stop order SELL / 945000.0 / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_parent_order)
        .with(stop_order(side: 'SELL', trigger_price: 945_000.0, size: 0.2))
    end
  end

  context 'with offsetting positions' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.1), position(side: 'SELL', price: 1_100_000, size: 0.1)]
    end

    it 'does not send an order' do
      expect { run }.to output("You don't have any position now.\n").to_stdout
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end
end
