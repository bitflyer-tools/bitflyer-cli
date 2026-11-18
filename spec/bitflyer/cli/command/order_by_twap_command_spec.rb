require 'spec_helper'

describe OrderByTWAPCommand do
  let!(:private_client) { stub_private_client }
  let(:command) { described_class.new }
  let(:response) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }
  let(:request_durations) { [2, 2, 2] }
  let(:submission_times) { [] }

  before do
    now = 0.0
    allow(Process).to receive(:clock_gettime).and_call_original
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { now }
    allow(command).to receive(:sleep) { |duration| now += duration }
    allow(private_client).to receive(:send_child_order) do
      submission_times << now
      now += request_durations.fetch(submission_times.length - 1)
      response
    end
  end

  def run(interval: 10)
    command.run(thor_options(amount: 0.01, type: 'buy', number_of_times: 3, interval: interval))
  end

  it 'sends the given number of market orders' do
    expect { run }.to output.to_stdout
    expect(private_client).to have_received(:send_child_order)
      .with(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY', size: 0.01).exactly(3).times
  end

  it 'keeps the submission cadence despite request latency' do
    expect { run }.to output.to_stdout
    expect(submission_times).to eq([0, 10, 20])
    expect(command).to have_received(:sleep).with(8).twice
    expect(command).to have_received(:sleep).twice
  end

  it 'rejects a negative interval before submitting any orders' do
    expect { run(interval: -1) }.to raise_error(ArgumentError, 'interval must be nonnegative')
    expect(private_client).not_to have_received(:send_child_order)
  end

  context 'when a request misses several submission deadlines' do
    let(:request_durations) { [25, 2, 2] }

    it 'starts a new cadence after the slow request finishes' do
      expect { run }.to output.to_stdout
      expect(submission_times).to eq([0, 35, 45])
      expect(command).to have_received(:sleep).with(10).once
      expect(command).to have_received(:sleep).with(8).once
      expect(command).to have_received(:sleep).twice
    end
  end

  context 'when an order is rejected' do
    let(:response) { { 'status' => -200 } }

    it 'prints the error response' do
      expect { run }.to output(/An error has occurred/).to_stdout
    end
  end
end
