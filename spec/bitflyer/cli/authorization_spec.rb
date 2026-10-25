require 'spec_helper'

describe Authorization do
  subject(:authorization) { Class.new { include Authorization }.new }

  around do |example|
    original = ENV.to_h.slice('BITFLYER_API_KEY', 'BITFLYER_API_SECRET')
    example.run
  ensure
    %w[BITFLYER_API_KEY BITFLYER_API_SECRET].each { |name| ENV[name] = original[name] }
  end

  context 'with credentials in the environment' do
    before do
      ENV['BITFLYER_API_KEY'] = 'key'
      ENV['BITFLYER_API_SECRET'] = 'secret'
    end

    it { expect(authorization.api_key).to eq('key') }
    it { expect(authorization.api_secret).to eq('secret') }
  end

  context 'without credentials' do
    before { %w[BITFLYER_API_KEY BITFLYER_API_SECRET].each { |name| ENV.delete(name) } }

    it { expect { authorization.api_key }.to output(/BITFLYER_API_KEY is not set/).to_stdout }
    it { expect { authorization.api_secret }.to output(/BITFLYER_API_SECRET is not set/).to_stdout }
  end
end
