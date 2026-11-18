require 'spec_helper'
require 'shellwords'

describe Bitflyer::Cli::Runner do
  let(:command) { double('command', run: nil) }
  let(:readme) { File.read(File.expand_path('../../README.md', __dir__)) }

  def start(*args)
    described_class.start(args)
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

  it 'passes options to order_by_best' do
    allow(OrderByBestCommand).to receive(:new).and_return(command)
    start('order_by_best', '-a', '0.01', '-t', 'buy')
    expect(command).to have_received(:run).with(hash_including('amount' => 0.01, 'type' => 'buy'))
  end

  it 'passes options to order_by_twap' do
    allow(OrderByTWAPCommand).to receive(:new).and_return(command)
    start('order_by_twap', '-a', '0.01', '-t', 'sell', '-n', '3', '-i', '10')
    expect(command).to have_received(:run)
      .with(hash_including('amount' => 0.01, 'type' => 'sell', 'number_of_times' => 3, 'interval' => 10))
  end

  it 'rejects a fractional TWAP order count without sending orders' do
    private_client = stub_private_client
    allow(private_client).to receive(:send_child_order)

    expect { start('order_by_twap', '-a', '0.01', '-t', 'buy', '--number-of-times', '1.9', '-i', '0') }
      .to output(/--number-of-times must be a whole number/).to_stderr
    expect(private_client).not_to have_received(:send_child_order)
  end

  it 'rejects a negative TWAP interval before sending any orders' do
    client = stub_private_client
    stub_responses(client, send_child_order: { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' })

    expect do
      start('order_by_twap', '--amount', '0.01', '--type', 'buy', '--number-of-times', '2', '--interval', '-1')
    end.to output(/^Invalid interval: --interval must be non-negative\.$/).to_stderr
    expect(client).not_to have_received(:send_child_order)
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
    expect { start('order_by_best', '-a', '0.01') }.to output(/required options/).to_stderr
    expect(OrderByBestCommand).not_to have_received(:new)
  end

  def readme_args(command_name)
    line = readme.each_line.find { |entry| entry.lstrip.start_with?("bitflyer #{command_name} ") }
    expect(line).not_to be_nil
    Shellwords.split(line.split('#', 2).first).drop(1)
  end
end
