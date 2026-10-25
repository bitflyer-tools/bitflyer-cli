require 'spec_helper'

describe Position do
  subject(:model) { described_class.new(positions) }

  context 'without positions' do
    let(:positions) { [] }

    it { is_expected.to be_empty }
    it { expect(model.size).to eq(0) }
    it { expect(model.average).to eq(0) }
    it { expect(model.profit(1_000_000)).to eq(0) }
  end

  context 'with long positions' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.1), position(side: 'BUY', price: 1_030_000, size: 0.2)]
    end

    it { is_expected.not_to be_empty }
    it { expect(model.size).to eq(0.3) }
    it { expect(model.average).to eq(1_020_000) }
    it { expect(model.profit(1_040_000)).to eq(6000) }
  end

  context 'with a short position' do
    let(:positions) { [position(side: 'SELL', price: 1_000_000, size: 0.5)] }

    it { expect(model.size).to eq(-0.5) }
    it { expect(model.average).to eq(1_000_000) }
    it { expect(model.profit(990_000)).to eq(5000) }
  end
end
