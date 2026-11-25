require 'spec_helper'

describe Bitflyer::Cli::OrderRejected do
  let(:response) { Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(status, body) }

  describe '.classify' do
    subject(:result) { described_class.classify(response, 'child_order_acceptance_id') }

    context 'when the body is not a Hash' do
      let(:status) { 200 }
      let(:body) { nil }

      it { is_expected.to eq(:unverified) }
    end

    context 'when the HTTP status is successful and an acceptance ID is present' do
      let(:status) { 200 }
      let(:body) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

      it { is_expected.to eq(:accepted) }
    end

    context 'when the HTTP status is successful but the body also carries an error message' do
      let(:status) { 200 }
      let(:body) do
        { 'child_order_acceptance_id' => 'JRF20180101-000000-000001', 'error_message' => 'Duplicate order' }
      end

      it { is_expected.to eq(:unverified) }
    end

    context 'when the HTTP status is successful and the exchange status is negative' do
      let(:status) { 200 }
      let(:body) { { 'status' => -200 } }

      it { is_expected.to eq(:rejected) }
    end

    context 'when the HTTP status is a client error and the exchange status is negative' do
      let(:status) { 400 }
      let(:body) { { 'status' => -205 } }

      it { is_expected.to eq(:rejected) }
    end

    context 'when the HTTP status is 408 and the exchange status is negative' do
      let(:status) { 408 }
      let(:body) { { 'status' => -205 } }

      it { is_expected.to eq(:unverified) }
    end

    context 'when the acceptance ID is present but blank' do
      let(:status) { 200 }
      let(:body) { { 'child_order_acceptance_id' => '   ' } }

      it { is_expected.to eq(:unverified) }
    end

    context 'when the acceptance ID is not a string' do
      let(:status) { 200 }
      let(:body) { { 'child_order_acceptance_id' => 1 } }

      it { is_expected.to eq(:unverified) }
    end
  end

  describe '.check_submission!' do
    context 'when the HTTP status is successful and the acceptance ID is valid' do
      let(:status) { 200 }
      let(:body) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

      it 'does not raise' do
        expect { described_class.check_submission!(response, 'child_order_acceptance_id') }.not_to raise_error
      end
    end

    context 'when the HTTP status is a client error and the exchange rejected the order' do
      let(:status) { 400 }
      let(:body) { { 'status' => -205, 'error_message' => 'Insufficient funds' } }

      it 'raises with the exchange rejection message' do
        expect { described_class.check_submission!(response, 'child_order_acceptance_id') }
          .to raise_error(described_class, 'Insufficient funds')
      end
    end

    context 'when the HTTP status cannot be classified as accepted or rejected' do
      let(:status) { 500 }
      let(:body) { { 'status' => -205 } }

      it 'raises Unverified naming the HTTP status' do
        expect { described_class.check_submission!(response, 'child_order_acceptance_id') }
          .to raise_error(described_class::Unverified, 'Could not verify order acceptance (HTTP 500).')
      end
    end
  end

  describe '.check!' do
    context 'when the response is not a Hash' do
      it 'raises Unverified' do
        expect { described_class.check!(nil, 'child_order_acceptance_id') }
          .to raise_error(described_class::Unverified, 'Could not verify order acceptance.')
      end
    end

    context 'when the acceptance ID is valid' do
      it 'does not raise' do
        body = { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' }
        expect { described_class.check!(body, 'child_order_acceptance_id') }.not_to raise_error
      end
    end

    context 'when there is no acceptance ID and no rejection evidence' do
      it 'raises Unverified' do
        expect { described_class.check!({}, 'child_order_acceptance_id') }
          .to raise_error(described_class::Unverified, 'Could not verify order acceptance.')
      end
    end

    context 'when the exchange rejected the order' do
      it 'raises with the exchange rejection message' do
        body = { 'status' => -205, 'error_message' => 'Insufficient funds' }
        expect { described_class.check!(body, 'child_order_acceptance_id') }
          .to raise_error(described_class, 'Insufficient funds')
      end
    end
  end

  describe '.raise_rejection!' do
    it 'raises with the exchange error message' do
      expect { described_class.raise_rejection!('error_message' => 'Insufficient funds') }
        .to raise_error(described_class, 'Insufficient funds')
    end

    it 'falls back to the inspected response when there is no error message' do
      response = { 'status' => -205 }
      expect { described_class.raise_rejection!(response) }
        .to raise_error(described_class, "Order rejected: #{response.inspect}")
    end
  end

  describe '.acceptance_id?' do
    it { expect(described_class.acceptance_id?('JRF20180101-000000-000001')).to be(true) }
    it { expect(described_class.acceptance_id?('')).to be(false) }
    it { expect(described_class.acceptance_id?('   ')).to be(false) }
    it { expect(described_class.acceptance_id?(nil)).to be(false) }
    it { expect(described_class.acceptance_id?(1)).to be(false) }
  end
end
