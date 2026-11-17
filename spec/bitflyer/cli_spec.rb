require 'spec_helper'
require 'shellwords'

describe Bitflyer::Cli::Runner do
  let(:command) { double('command', run: nil) }
  let(:readme) { File.read(File.expand_path('../../README.md', __dir__)) }

  def start(*args)
    described_class.start(args)
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
