require 'spec_helper'

describe 'Order previews' do
  let(:ifdoco_args) { %w[ifdoco_by_range -a=0.01 -t=buy -r=10001 -p=60 --dry-run] }
  let(:twap_args) { %w[order_by_twap -a=0.1 -t=sell -n=3 -i=0.1 --dry-run] }

  before do
    expect(Bitflyer).not_to receive(:http_private_client)
    expect(Bitflyer::Cli::PersistentHTTPClient).not_to receive(:new)
  end

  it 'previews the exact rounded IFDOCO legs using the public ticker' do
    public_client = stub_public_client
    stub_responses(public_client, ticker: { 'ltp' => 1_000_000 })

    expect { Bitflyer::Cli::Runner.start(ifdoco_args) }.to output(<<~OUTPUT).to_stdout
      IFDOCO dry run (FX_BTC_JPY)
      Reference price: 1000000 JPY
      Market entry: BUY 0.01 BTC
      Take-profit limit: SELL 0.01 BTC at 1006000 JPY
      Stop trigger: SELL 0.01 BTC at 995999 JPY
    OUTPUT
    expect(public_client).to have_received(:ticker).with(product_code: 'FX_BTC_JPY').once
  end

  it 'previews TWAP totals and timing without network access or scheduling' do
    twap = OrderByTWAPCommand.new
    allow(OrderByTWAPCommand).to receive(:new).and_return(twap)
    expect(Bitflyer).not_to receive(:http_public_client)
    expect(twap).not_to receive(:monotonic_time)
    expect(twap).not_to receive(:sleep)

    expect { Bitflyer::Cli::Runner.start(twap_args) }.to output(<<~OUTPUT).to_stdout
      TWAP dry run (FX_BTC_JPY)
      Side: SELL
      Size per slice: 0.1 BTC
      Slice count: 3
      Total size: 0.3 BTC
      Interval: 0.1 seconds
      Planned time from first to last slice: 0.2 seconds
    OUTPUT
  end

  it 'shows zero planned time for a single TWAP slice' do
    args = twap_args.map { |arg| arg == '-n=3' ? '-n=1' : arg }
    expect { Bitflyer::Cli::Runner.start(args) }
      .to output(/Planned time from first to last slice: 0\.0 seconds/).to_stdout
  end

  it 'rejects an IFDOCO exit price that rounds to the reference price' do
    public_client = stub_public_client
    stub_responses(public_client, ticker: { 'ltp' => 1_000_000 })

    args = ifdoco_args.map { |arg| arg == '-r=10001' ? '-r=1' : arg }
    expect_invalid(args, /must strictly bracket the reference price after rounding/)
  end

  it 'rejects an invalid IFDOCO amount before fetching the ticker' do
    expect(Bitflyer).not_to receive(:http_public_client)
    args = ifdoco_args.map { |arg| arg == '-a=0.01' ? '-a=0' : arg }
    expect_invalid(args, /Amount must be positive and finite/)
  end

  it 'rejects a fractional TWAP slice count' do
    args = twap_args.map { |arg| arg == '-n=3' ? '-n=1.5' : arg }
    expect_invalid(args, /--number-of-times must be a positive whole number/)
  end

  def expect_invalid(args, message)
    expect do
      expect { Bitflyer::Cli::Runner.start(args) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(message).to_stderr
  end
end
