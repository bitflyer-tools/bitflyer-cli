require 'spec_helper'

describe String do
  describe '#split_by_comma' do
    it { expect('1234567'.split_by_comma).to eq('1,234,567') }
    it { expect('123'.split_by_comma).to eq('123') }
    it { expect('-1234.5'.split_by_comma).to eq('-1,234.5') }
  end

  describe '#color_with_number' do
    it 'prefixes non-negative numbers with a plus and colors them green' do
      expect('100'.color_with_number(100)).to eq("+#{'100'.colorize(:green)}")
    end

    it 'colors negative numbers red' do
      expect('-100'.color_with_number(-100)).to eq('-100'.colorize(:red))
    end
  end
end
