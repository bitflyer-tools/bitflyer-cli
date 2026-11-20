require 'spec_helper'

describe IFDOCOByRangeCommand do
  let!(:public_client) { stub_public_client }
  let!(:private_client) { stub_private_client }
  let(:response) { { 'parent_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(public_client, ticker: { 'ltp' => 1_000_000 })
    stub_responses(private_client, send_parent_order: response)
  end

  def run(type, **overrides)
    options = { amount: 0.01, type: type, range: 10_000, percentage: 60 }.merge(overrides)
    described_class.new.run(thor_options(**options))
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

  [Float::INFINITY, -Float::INFINITY, Float::NAN].each do |amount|
    it "rejects a non-finite amount of #{amount}" do
      expect { run('buy', amount: amount) }.to raise_error(Thor::Error, 'Amount must be positive and finite.')
      expect(public_client).not_to have_received(:ticker)
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end

  it 'splits the range into profit and loss lines for a buy' do
    expect { run('buy') }.to output(<<~OUTPUT).to_stdout
      Send market order BUY / 0.01
      Set limit order SELL / 1006000 / 0.01
      Set stop order SELL / 996000 / 0.01
    OUTPUT
    expect(private_client).to have_received(:send_parent_order)
      .with(**ifdoco_order(side: 'BUY', counter_side: 'SELL', profit_price: 1_006_000, loss_price: 996_000))
  end

  it 'mirrors the lines for a sell' do
    expect { run('sell') }.to output(<<~OUTPUT).to_stdout
      Send market order SELL / 0.01
      Set limit order BUY / 994000 / 0.01
      Set stop order BUY / 1004000 / 0.01
    OUTPUT
    expect(private_client).to have_received(:send_parent_order)
      .with(**ifdoco_order(side: 'SELL', counter_side: 'BUY', profit_price: 994_000, loss_price: 1_004_000))
  end

  it 'reports a ticker rejection before submitting an IFDOCO order' do
    stub_responses(public_client, ticker: { 'status' => -1, 'error_message' => 'Ticker unavailable' })

    expect { run('buy') }.to raise_error(HasHTTPClient::TickerError, 'Ticker error: Ticker unavailable')
    expect(private_client).not_to have_received(:send_parent_order)
  end

  it 'rejects an unexpected ticker response' do
    stub_responses(public_client, ticker: nil)

    expect { run('buy') }.to raise_error(HasHTTPClient::TickerError, /Ticker error: unexpected response/)
    expect(private_client).not_to have_received(:send_parent_order)
  end

  [{}, { 'ltp' => 0 }, { 'ltp' => -1 }, { 'ltp' => 'unavailable' }, { 'ltp' => Float::INFINITY }].each do |ticker|
    it "rejects a ticker with an unusable last traded price (#{ticker.inspect})" do
      stub_responses(public_client, ticker: ticker)

      expect { run('buy') }.to raise_error(HasHTTPClient::TickerError, /Ticker error: ltp/)
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end

  %w[buy sell].each do |side|
    context "for a #{side} order" do
      [
        [{ amount: 0 }, /Amount must be positive/],
        [{ amount: -0.01 }, /Amount must be positive/],
        [{ range: 0 }, /Range must be positive/],
        [{ range: -10_000 }, /Range must be positive/],
        [{ range: Float::INFINITY }, /Range must be positive and finite/],
        [{ percentage: -1 }, /Percentage must be greater than 0 and less than 100/],
        [{ percentage: 0 }, /Percentage must be greater than 0 and less than 100/],
        [{ percentage: 100 }, /Percentage must be greater than 0 and less than 100/],
        [{ percentage: 120 }, /Percentage must be greater than 0 and less than 100/]
      ].each do |options, message|
        it "rejects #{options} before fetching the reference price" do
          expect { run(side, **options) }.to raise_error(Thor::Error, message)
          expect(public_client).not_to have_received(:ticker)
          expect(private_client).not_to have_received(:send_parent_order)
        end
      end

      it 'rejects an integer exit price equal to the reference price' do
        expect { run(side, range: 1, percentage: 50) }
          .to raise_error(Thor::Error, /must strictly bracket the reference price after rounding/)
        expect(private_client).not_to have_received(:send_parent_order)
      end

      it 'rejects a range that overflows the exit price calculation' do
        expect { run(side, range: Float::MAX) }.to raise_error(Thor::Error, /Exit prices must be finite/)
        expect(private_client).not_to have_received(:send_parent_order)
      end
    end
  end

  it 'rejects an unknown order type before fetching the reference price' do
    expect { run('unknown') }.to raise_error(Thor::Error, /Order type must be buy or sell/)
    expect(public_client).not_to have_received(:ticker)
    expect(private_client).not_to have_received(:send_parent_order)
  end

  context 'when the order is rejected' do
    let(:response) { { 'status' => -200 } }

    it 'prints the error response' do
      expect { run('buy') }.to output(/An error has occurred/).to_stdout
    end
  end
end
