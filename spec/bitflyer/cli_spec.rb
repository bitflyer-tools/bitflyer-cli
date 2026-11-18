require 'spec_helper'

describe Bitflyer::Cli::Runner do
  let(:command) { double('command', run: nil) }

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
    allow(command).to receive(:run).and_return(accepted: 3, rejected: 0)
    start('order_by_twap', '-a', '0.01', '-t', 'sell', '-n', '3', '-i', '10')
    expect(command).to have_received(:run)
      .with(hash_including('amount' => 0.01, 'type' => 'sell', 'number_of_times' => 3, 'interval' => 10))
  end

  describe 'order_by_twap submission results' do
    let!(:private_client) { stub_private_client }
    let(:acceptance) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

    before do
      twap = OrderByTWAPCommand.new
      allow(twap).to receive(:sleep)
      allow(OrderByTWAPCommand).to receive(:new).and_return(twap)
    end

    def start_twap
      start('order_by_twap', '-a', '0.01', '-t', 'buy', '-n', '3', '-i', '10')
    end

    it 'reports all slices and exits unsuccessfully when a middle slice is rejected' do
      allow(private_client).to receive(:send_child_order).and_return(acceptance, { 'status' => -200 }, acceptance)

      expect do
        expect { start_twap }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/TWAP exchange acceptance \(slices\): 2 accepted, 1 rejected/).to_stdout
      expect(private_client).to have_received(:send_child_order).exactly(3).times
    end

    it 'reports all slices and returns normally when every slice is accepted' do
      stub_responses(private_client, send_child_order: acceptance)

      expect { start_twap }.to output(/TWAP exchange acceptance \(slices\): 3 accepted, 0 rejected/).to_stdout
    end
  end

  it 'passes options to stop_by_range' do
    allow(StopByRangeCommand).to receive(:new).and_return(command)
    start('stop_by_range', '-r', '5000')
    expect(command).to have_received(:run).with(hash_including('range' => 5000))
  end

  it 'passes options to ifdoco_by_range' do
    allow(IFDOCOByRangeCommand).to receive(:new).and_return(command)
    start('ifdoco_by_range', '-a', '0.01', '-t', 'buy', '-r', '10000', '-p', '60')
    expect(command).to have_received(:run)
      .with(hash_including('amount' => 0.01, 'type' => 'buy', 'range' => 10_000, 'percentage' => 60))
  end

  it 'does not run a command when a required option is missing' do
    allow(OrderByBestCommand).to receive(:new)
    expect { start('order_by_best', '-a', '0.01') }.to output(/required options/).to_stderr
    expect(OrderByBestCommand).not_to have_received(:new)
  end
end
