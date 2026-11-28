require 'spec_helper'

describe Bitflyer::Cli::AlertNotifier do
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPOK, code: '200') }

  before do
    allow(Net::HTTP).to receive(:start).with('example.com', 443, use_ssl: true).and_yield(http)
    allow(http).to receive(:request).and_return(response)
  end

  def check_alerts(price:, balance:)
    notifier.check(price: price, balance: balance) { |message| notifier.deliver(message) }
  end

  describe '#check with an alert price' do
    subject(:notifier) { described_class.new(webhook_url: 'https://example.com/hook', alert_price: 1_000_000) }

    it 'does not notify on the first observed reading, even when already past the threshold' do
      check_alerts(price: 1_100_000, balance: nil)

      expect(http).not_to have_received(:request)
    end

    it 'notifies once when the price crosses the threshold upward' do
      check_alerts(price: 999_000, balance: nil)
      check_alerts(price: 1_000_000, balance: nil)

      expect(http).to have_received(:request).once
    end

    it 'notifies once when the price crosses the threshold downward' do
      check_alerts(price: 1_000_000, balance: nil)
      check_alerts(price: 999_999, balance: nil)

      expect(http).to have_received(:request).once
    end

    it 'does not notify again while the price stays on the same side' do
      check_alerts(price: 999_000, balance: nil)
      check_alerts(price: 1_000_000, balance: nil)
      check_alerts(price: 1_100_000, balance: nil)

      expect(http).to have_received(:request).once
    end

    it 'notifies on each crossing, including the return to the first observed side' do
      check_alerts(price: 999_000, balance: nil)
      check_alerts(price: 1_000_000, balance: nil)
      check_alerts(price: 999_000, balance: nil)
      check_alerts(price: 1_000_000, balance: nil)

      expect(http).to have_received(:request).exactly(3).times
    end

    it 'ignores a missing price' do
      check_alerts(price: nil, balance: nil)
      check_alerts(price: nil, balance: nil)

      expect(http).not_to have_received(:request)
    end

    it 'sends a Slack/Discord-compatible JSON payload' do
      allow(http).to receive(:request) do |request|
        expect(request).to be_a(Net::HTTP::Post)
        body = JSON.parse(request.body)
        expect(body['text']).to match(/Price alert/)
        expect(body['content']).to eq(body['text'])
        response
      end

      check_alerts(price: 999_000, balance: nil)
      check_alerts(price: 1_000_000, balance: nil)
    end
  end

  describe '#check with an alert balance' do
    subject(:notifier) { described_class.new(webhook_url: 'https://example.com/hook', alert_balance: 50_000) }

    it 'does not notify on the first observed reading, even when already below the threshold' do
      check_alerts(price: nil, balance: 10_000)

      expect(http).not_to have_received(:request)
    end

    it 'notifies once when the balance drops below the threshold' do
      check_alerts(price: nil, balance: 60_000)
      check_alerts(price: nil, balance: 40_000)

      expect(http).to have_received(:request).once
    end

    it 'does not notify when the balance recovers above the threshold' do
      check_alerts(price: nil, balance: 40_000)
      check_alerts(price: nil, balance: 60_000)

      expect(http).not_to have_received(:request)
    end

    it 'ignores a missing balance' do
      check_alerts(price: nil, balance: nil)
      check_alerts(price: nil, balance: nil)

      expect(http).not_to have_received(:request)
    end
  end

  describe '#check without any configured threshold' do
    subject(:notifier) { described_class.new(webhook_url: 'https://example.com/hook') }

    it 'never notifies' do
      check_alerts(price: 2_000_000, balance: 10)
      check_alerts(price: 1, balance: 2_000_000)

      expect(http).not_to have_received(:request)
    end
  end

  describe 'webhook delivery failures' do
    subject(:notifier) { described_class.new(webhook_url: 'https://example.com/hook', alert_price: 1_000_000) }

    it 'warns instead of raising when the webhook request fails' do
      allow(Net::HTTP).to receive(:start).and_raise(SocketError, 'getaddrinfo failed')

      check_alerts(price: 999_000, balance: nil)

      expect { check_alerts(price: 1_000_000, balance: nil) }
        .to output("Failed to send alert webhook: SocketError\n").to_stderr
    end

    %w[404 503].each do |status|
      it "warns once on HTTP #{status} and continues checking later crossings" do
        failed_response = instance_double(Net::HTTPResponse, code: status)
        allow(http).to receive(:request).and_return(failed_response, response)
        check_alerts(price: 999_000, balance: nil)

        expect do
          check_alerts(price: 1_000_000, balance: nil)
          check_alerts(price: 1_100_000, balance: nil)
          check_alerts(price: 999_000, balance: nil)
        end.to output("Failed to send alert webhook: HTTP #{status}\n").to_stderr
        expect(http).to have_received(:request).twice
      end
    end
  end
end
