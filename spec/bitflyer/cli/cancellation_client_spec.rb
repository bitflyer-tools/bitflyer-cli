require 'spec_helper'

describe CancellationClient do
  describe '#post' do
    subject(:result) { described_class.new('key', 'secret').post(path, params) }

    let(:path) { '/v1/me/cancelchildorder' }
    let(:params) { { 'child_order_id' => 'JOR1' } }
    let(:client) { instance_double(Bitflyer::Cli::PersistentHTTPClient, close: nil) }
    let(:body) { '{"status":-205,"error_message":"Order error"}' }

    before do
      response = instance_double(Net::HTTPResponse, code: code, body: body)
      allow(client).to receive(:cancel).with(path, params).and_return(response)
      allow(Bitflyer::Cli::PersistentHTTPClient).to receive(:new).with('key', 'secret').and_return(client)
    end

    context 'when HTTP 200 has an empty body' do
      let(:code) { '200' }
      let(:body) { '' }

      it { is_expected.to eq(described_class::Result.new(:accepted, '200', nil, nil)) }
    end

    %w[200 400].each do |http_code|
      context "when HTTP #{http_code} has a negative exchange status" do
        let(:code) { http_code }

        it { is_expected.to eq(described_class::Result.new(:rejected, http_code, -205, 'Order error')) }
      end
    end

    %w[307 408 503].each do |http_code|
      context "when HTTP #{http_code} has a negative exchange status" do
        let(:code) { http_code }

        it { is_expected.to eq(described_class::Result.new(:unverified, http_code, nil, nil)) }
      end
    end
  end

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
