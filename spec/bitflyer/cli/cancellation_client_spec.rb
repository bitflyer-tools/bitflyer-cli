require 'spec_helper'

describe CancellationClient do
  it 'treats any class added to PersistentHTTPClient::COMMUNICATION_ERRORS as an unverified outcome' do
    custom_communication_error = Class.new(StandardError)
    stub_const('Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS', [custom_communication_error].freeze)
    client = instance_double(Bitflyer::Cli::PersistentHTTPClient, close: nil)
    allow(client).to receive(:cancel).and_raise(custom_communication_error)
    allow(Bitflyer::Cli::PersistentHTTPClient).to receive(:new).with('key', 'secret').and_return(client)

    result = described_class.new('key', 'secret').post('/v1/me/cancelchildorder', 'child_order_id' => 'JOR1')

    expect(result).to eq(described_class::Result.new(:unverified, nil, nil, nil))
    expect(client).to have_received(:close)
  end
end
