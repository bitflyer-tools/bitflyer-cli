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

  describe CancellationClient::Result do
    describe '#failure_message' do
      it 'returns the exchange message when the result is rejected with a message' do
        result = described_class.new(:rejected, '200', -205, 'Order not found.')

        expect(result.failure_message('unverified', 'fallback')).to eq('Order not found.')
      end

      it 'returns the fallback text when the result is rejected without a message' do
        result = described_class.new(:rejected, '200', -205, '')

        expect(result.failure_message('unverified', 'fallback')).to eq('fallback')
      end

      it 'includes the HTTP status when the result is unverified with any HTTP code' do
        result = described_class.new(:unverified, '404', nil, nil)

        expect(result.failure_message('unverified', 'fallback')).to eq('unverified (HTTP 404).')
      end

      it 'omits the HTTP status when the result is unverified without an HTTP code' do
        result = described_class.new(:unverified, nil, nil, nil)

        expect(result.failure_message('unverified', 'fallback')).to eq('unverified.')
      end
    end
  end
end
