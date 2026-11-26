require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'shellwords'

describe Bitflyer::Cli::Runner do
  let(:command) { double('command', run: nil) }
  let(:readme) { File.read(File.expand_path('../../README.md', __dir__)) }

  def start(*args)
    described_class.start(args)
  end

  it 'preserves existing String formatters when loading the CLI' do
    lib = File.expand_path('../../lib', __dir__)
    output, status = Open3.capture2e(RbConfig.ruby, '-I', lib, '-e', <<~'RUBY')
      class String
        def split_by_comma
          :original_grouping
        end

        def color_with_number(_number)
          :original_coloring
        end
      end

      require 'bitflyer/cli'

      abort 'String#split_by_comma changed' unless '1000'.split_by_comma == :original_grouping
      abort 'String#color_with_number changed' unless '1000'.color_with_number(1000) == :original_coloring
    RUBY

    expect(status).to be_success, output
  end

  it 'shows usage for an individual command' do
    expect { start('help', 'order_by_best') }.to output(/order_by_best.*--amount=amount.*--type=buy\/sell/).to_stdout
  end

  it 'runs cancel_all' do
    allow(CancelAllCommand).to receive(:new).and_return(command)
    start('cancel_all')
    expect(command).to have_received(:run).with(no_args)
  end

  it 'runs counter_trade' do
    allow(CounterTradeCommand).to receive(:new).and_return(command)
    start('counter_trade')
    expect(command).to have_received(:run).with(no_args)
  end

  it 'runs summary' do
    allow(SummaryCommand).to receive(:new).and_return(command)
    start('summary')
    expect(command).to have_received(:run).with(no_args)
  end

  it 'passes alert options to summary' do
    allow(SummaryCommand).to receive(:new).and_return(command)
    start('summary', '--notify-webhook=https://example.com/hook', '--alert-price=1000000', '--alert-balance=40000')
    expect(SummaryCommand).to have_received(:new).with(
      hash_including('notify_webhook' => 'https://example.com/hook', 'alert_price' => 1_000_000, 'alert_balance' => 40_000)
    )
    expect(command).to have_received(:run).with(no_args)
  end

  it 'passes options to order_by_best' do
    allow(OrderByBestCommand).to receive(:new).and_return(command)
    start('order_by_best', '-a', '0.01', '-t', 'buy')
    expect(command).to have_received(:run).with(hash_including('amount' => 0.01, 'type' => 'buy'))
  end

  it 'passes options to order_by_twap' do
    allow(OrderByTWAPCommand).to receive(:new).and_return(command)
    allow(command).to receive(:run).and_return(accepted: 3, rejected: 0, unverified: 0, unattempted: 0)
    start('order_by_twap', '-a', '0.01', '-t', 'sell', '-n', '3', '-i', '10')
    expect(command).to have_received(:run)
      .with(hash_including('amount' => 0.01, 'type' => 'sell', 'number_of_times' => 3, 'interval' => 10))
  end

  {
    'order_by_best' => [],
    'order_by_twap' => %w[--number-of-times=2 --interval=10],
    'ifdoco_by_range' => %w[--range=10000 --percentage=60]
  }.each do |name, strategy_options|
    %w[0 -0.01].each do |amount|
      it "rejects an amount of #{amount} for #{name} before doing exchange or scheduling work" do
        public_client = stub_public_client
        private_client = stub_private_client
        expect(public_client).not_to receive(:ticker)
        expect(private_client).not_to receive(:send_child_order)
        expect(private_client).not_to receive(:send_parent_order)

        if name == 'order_by_twap'
          twap = OrderByTWAPCommand.new
          allow(OrderByTWAPCommand).to receive(:new).and_return(twap)
          expect(twap).not_to receive(:monotonic_time)
          expect(twap).not_to receive(:sleep)
        end

        expect do
          expect { start(name, "--amount=#{amount}", '--type=buy', *strategy_options) }
            .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output(/^Amount must be positive and finite\.$/).to_stderr
      end
    end
  end

  describe 'order_by_twap submission results' do
    let!(:private_client) { stub_persistent_client }
    let(:acceptance) do
      Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, 'child_order_acceptance_id' => 'JRF20180101-000000-000001')
    end

    before do
      twap = OrderByTWAPCommand.new
      allow(twap).to receive(:sleep)
      allow(OrderByTWAPCommand).to receive(:new).and_return(twap)
    end

    def start_twap
      start('order_by_twap', '-a', '0.01', '-t', 'buy', '-n', '3', '-i', '10')
    end

    it 'reports all slices and exits unsuccessfully when a middle slice is rejected' do
      rejection = Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(400, 'status' => -200)
      allow(private_client).to receive(:send_child_order).and_return(acceptance, rejection, acceptance)

      expect do
        expect { start_twap }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/TWAP exchange acceptance \(slices\): 2 accepted, 1 rejected/).to_stdout
      expect(private_client).to have_received(:send_child_order).exactly(3).times
    end

    it 'reports all slices and returns normally when every slice is accepted' do
      stub_responses(private_client, send_child_order: acceptance)

      expect { start_twap }.to output(/TWAP exchange acceptance \(slices\): 3 accepted, 0 rejected/).to_stdout
    end

    it 'reports partial results and stops submitting when a slice times out' do
      expect(private_client).to receive(:send_child_order).ordered.and_return(acceptance)
      expect(private_client).to receive(:send_child_order).ordered.and_raise(Net::ReadTimeout)

      expect do
        expect { start_twap }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/TWAP exchange acceptance \(slices\): 1 accepted, 0 rejected, 1 unverified, 1 unattempted\./).to_stdout
      expect(private_client).to have_received(:close).once
    end
  end

  %w[0 -1 1.9].each do |count|
    it "rejects a TWAP order count of #{count} without sending orders" do
      private_client = stub_persistent_client
      allow(private_client).to receive(:send_child_order)

      expect do
        expect do
          start('order_by_twap', '-a', '0.01', '-t', 'buy', "--number-of-times=#{count}", '-i', '0')
        end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/^--number-of-times must be a positive whole number$/).to_stderr
      expect(private_client).not_to have_received(:send_child_order)
    end
  end

  it 'rejects an unsupported TWAP order type without sending orders' do
    client = stub_persistent_client
    stub_responses(client, send_child_order: { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' })

    expect do
      expect do
        start('order_by_twap', '--amount', '0.01', '--type', 'hold', '--number-of-times', '2', '--interval', '0')
      end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/^Order type must be buy or sell$/).to_stderr
    expect(client).not_to have_received(:send_child_order)
  end

  {
    'negative' => '-1',
    'overflowing' => "#{'9' * 310}.0",
    'finite but outside the supported range' => (10**100).to_s
  }.each do |description, interval|
    it "rejects the #{description} TWAP interval before sending any orders" do
      client = stub_persistent_client
      acceptance = Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, 'child_order_acceptance_id' => 'JRF20180101-000000-000001')
      stub_responses(client, send_child_order: acceptance)

      expect do
        expect do
          start('order_by_twap', '-a', '0.01', '-t', 'buy', '-n', '2', "--interval=#{interval}")
        end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/^--interval must be 0\.\.2147483647$/).to_stderr
      expect(client).not_to have_received(:send_child_order)
    end
  end

  it 'passes options from the README stop_by_range example' do
    allow(StopByRangeCommand).to receive(:new).and_return(command)
    start(*readme_args('stop_by_range'))
    expect(command).to have_received(:run).with(hash_including('range' => 5000))
  end

  it 'passes options from the README ifdoco_by_range example' do
    allow(IFDOCOByRangeCommand).to receive(:new).and_return(command)
    start(*readme_args('ifdoco_by_range'))
    expect(command).to have_received(:run)
      .with(hash_including('amount' => 0.01, 'type' => 'buy', 'range' => 10_000, 'percentage' => 60))
  end

  it 'does not run a command when a required option is missing' do
    allow(OrderByBestCommand).to receive(:new)
    expect do
      expect { start('order_by_best', '-a', '0.01') }.to raise_error(SystemExit)
    end.to output(/required options/).to_stderr
    expect(OrderByBestCommand).not_to have_received(:new)
  end

  def readme_args(command_name)
    line = readme.each_line.find { |entry| entry.lstrip.start_with?("bitflyer #{command_name} ") }
    expect(line).not_to be_nil
    Shellwords.split(line.split('#', 2).first).drop(1)
  end
end
