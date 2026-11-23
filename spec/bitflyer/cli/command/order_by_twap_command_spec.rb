require 'spec_helper'

describe OrderByTWAPCommand do
  let!(:private_client) { stub_persistent_client }
  let(:command) { described_class.new }
  let(:response) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }
  let(:number_of_times) { 3 }
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
      Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, response)
    end
  end

  def run(interval: 10, amount: 0.01, type: 'buy')
    command.run(thor_options(amount: amount, type: type, number_of_times: number_of_times, interval: interval))
  end

  [Float::INFINITY, -Float::INFINITY, Float::NAN].each do |amount|
    it "rejects a non-finite amount of #{amount}" do
      expect(command).not_to receive(:monotonic_time)
      expect { run(amount: amount) }.to raise_error(Thor::Error, 'Amount must be positive and finite.')
      expect(command).not_to have_received(:sleep)
      expect(private_client).not_to have_received(:send_child_order)
    end
  end

  it 'sends the given number of market orders' do
    expect { run }.to output.to_stdout
    expect(private_client).to have_received(:send_child_order)
      .with(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY', size: 0.01).exactly(3).times
  end

  { 'bUy' => 'BUY', 'sElL' => 'SELL' }.each do |type, side|
    it "uses #{side} for every order when the type is #{type}" do
      expect { run(type: type) }.to output.to_stdout
      expect(private_client).to have_received(:send_child_order)
        .with(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: side, size: 0.01).exactly(3).times
    end
  end

  it 'keeps the submission cadence despite request latency' do
    expect { run }.to output.to_stdout
    expect(submission_times).to eq([0, 10, 20])
    expect(command).to have_received(:sleep).with(8).twice
    expect(command).to have_received(:sleep).twice
  end

  it 'submits every order without waiting when the interval is zero' do
    expect { run(interval: 0) }.to output(/3 accepted/).to_stdout
    expect(submission_times).to eq([0, 2, 4])
    expect(command).not_to have_received(:sleep)
  end

  it 'reports the remaining slices as unattempted when a wait is interrupted' do
    allow(command).to receive(:sleep).and_raise(Interrupt)

    expect do
      expect { run }.to raise_error(Interrupt)
    end.to output(/1 accepted, 0 rejected, 0 unverified, 2 unattempted\./).to_stdout

    expect(private_client).to have_received(:send_child_order).once
    expect(private_client).to have_received(:close).once
  end

  it 'reports the interrupted submission as unverified and stops the schedule' do
    allow(private_client).to receive(:send_child_order) do
      raise Interrupt unless submission_times.empty?

      submission_times << 0
      Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, response)
    end

    expect do
      expect { run }.to raise_error(Interrupt)
    end.to output(/1 accepted, 0 rejected, 1 unverified, 1 unattempted\./).to_stdout

    expect(private_client).to have_received(:send_child_order).twice
    expect(private_client).to have_received(:close).once
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

  context 'when requests finish immediately' do
    let(:request_durations) { [0, 0, 0] }

    it 'waits the full interval only between orders' do
      expect { run }.to output.to_stdout
      expect(submission_times).to eq([0, 10, 20])
      expect(command).to have_received(:sleep).with(10).twice
      expect(command).to have_received(:sleep).twice
    end
  end

  context 'when submitting a single order' do
    let(:number_of_times) { 1 }

    it 'prints the response without waiting' do
      expect { run }.to output(/#{response.fetch('child_order_acceptance_id')}/).to_stdout
      expect(private_client).to have_received(:send_child_order).once
      expect(command).not_to have_received(:sleep)
    end
  end

  context 'when the acceptance ID is a non-breaking space' do
    let(:response) { { 'child_order_acceptance_id' => "\u00A0" } }

    it 'reports the first slice as unverified and stops the schedule' do
      expect { run }.to output(/0 accepted, 0 rejected, 1 unverified, 2 unattempted/).to_stdout
      expect(private_client).to have_received(:send_child_order).once
      expect(command).not_to have_received(:sleep)
    end
  end

  context 'when an order is rejected' do
    let(:response) { { 'status' => -200 } }

    it 'reports rejected slices and preserves the submission cadence' do
      expect { run }.to output(/An error has occurred.*0 accepted, 3 rejected/m).to_stdout
      expect(submission_times).to eq([0, 10, 20])
    end
  end
end
