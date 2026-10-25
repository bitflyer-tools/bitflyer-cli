require 'spec_helper'

describe IFDOCOByRangeCommand do
  let!(:public_client) { stub_public_client }
  let!(:private_client) { stub_private_client }
  let(:response) { { 'parent_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(public_client, ticker: { 'ltp' => 1_000_000 })
    stub_responses(private_client, send_parent_order: response)
  end

  def run(type)
    described_class.new.run(thor_options(amount: 0.01, type: type, range: 10_000, percentage: 60))
  end

  def ifdoco_order(side:, counter_side:, profit_price:, loss_price:)
    {
      order_method: 'IFDOCO',
      time_in_force: 'GTC',
      parameters: [
        { product_code: 'FX_BTC_JPY', condition_type: 'MARKET', side: side, size: 0.01 },
        { product_code: 'FX_BTC_JPY', condition_type: 'LIMIT', side: counter_side, price: profit_price, size: 0.01 },
        { product_code: 'FX_BTC_JPY', condition_type: 'STOP', side: counter_side, trigger_price: loss_price,
          size: 0.01 }
      ]
    }
  end

  it 'splits the range into profit and loss lines for a buy' do
    expect { run('buy') }.to output(%r{Set limit order BUY / 1006000 / 0.01\nSet stop order BUY / 996000}).to_stdout
    expect(private_client).to have_received(:send_parent_order)
      .with(**ifdoco_order(side: 'BUY', counter_side: 'SELL', profit_price: 1_006_000, loss_price: 996_000))
  end

  it 'mirrors the lines for a sell' do
    expect { run('sell') }.to output(/Send market order SELL/).to_stdout
    expect(private_client).to have_received(:send_parent_order)
      .with(**ifdoco_order(side: 'SELL', counter_side: 'BUY', profit_price: 994_000, loss_price: 1_004_000))
  end

  context 'when the order is rejected' do
    let(:response) { { 'status' => -200 } }

    it 'prints the error response' do
      expect { run('buy') }.to output(/An error has occurred/).to_stdout
    end
  end
end
