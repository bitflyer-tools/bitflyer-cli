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

    it 'passes the API key and secret to the private HTTP client factory' do
      command = Class.new { include HasHTTPClient }.new
      client = double('private HTTP client')
      allow(Bitflyer).to receive(:http_private_client).with('key', 'secret').and_return(client)

      expect(command.http_private_client).to be(client)
    end
  end
end
