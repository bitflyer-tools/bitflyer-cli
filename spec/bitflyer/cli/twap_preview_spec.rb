require 'spec_helper'

describe Bitflyer::Cli::TWAPPreview do
  describe '.print' do
    it 'prints the side, slice plan, and totals' do
      expect { described_class.print('BUY', 0.01, 3, 10) }.to output(<<~OUTPUT).to_stdout
        TWAP dry run (FX_BTC_JPY)
        Side: BUY
        Size per slice: 0.01 BTC
        Slice count: 3
        Total size: 0.03 BTC
        Interval: 10 seconds
        Planned time from first to last slice: 20.0 seconds
      OUTPUT
    end

    it 'reports zero planned time for a single slice' do
      expect { described_class.print('SELL', 0.5, 1, 10) }.to output(<<~OUTPUT).to_stdout
        TWAP dry run (FX_BTC_JPY)
        Side: SELL
        Size per slice: 0.5 BTC
        Slice count: 1
        Total size: 0.5 BTC
        Interval: 10 seconds
        Planned time from first to last slice: 0.0 seconds
      OUTPUT
    end
  end
end
