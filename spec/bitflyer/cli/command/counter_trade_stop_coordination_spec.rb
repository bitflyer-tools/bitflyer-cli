# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

describe 'Coordinating protective stops with counter trades', :stop_state do
  let!(:private_client) { stub_persistent_client }
  let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.2)] }
  let(:child_order_accepted) do
    Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, { 'child_order_acceptance_id' => 'JRF-ct' })
  end
  let(:parent_order_accepted) do
    Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, { 'parent_order_acceptance_id' => 'JRF-stop' })
  end

  before do
    stub_responses(private_client, positions: positions, parent_orders: [],
                                   send_child_order: child_order_accepted, send_parent_order: parent_order_accepted)
  end

  def run_stop(range = 5000)
    StopByRangeCommand.new.run(thor_options(range: range))
  end

  def run_counter_trade
    CounterTradeCommand.new.run
  end

  it 'holds the same per-product lock for a counter trade and a stop submission' do
    thread = nil
    holding_lock = Queue.new
    release_lock = Queue.new
    allow(private_client).to receive(:send_child_order) do
      holding_lock << true
      release_lock.pop
      child_order_accepted
    end

    Timeout.timeout(5) do
      thread = Thread.new { run_counter_trade }
      holding_lock.pop

      lock_path = File.join(Bitflyer::Cli::CounterTradeSubmission.state_directory, 'FX_BTC_JPY.json.lock')
      File.open(lock_path, 'r+') do |file|
        expect(file.flock(File::LOCK_EX | File::LOCK_NB)).to be(false)
      end

      release_lock << true
      thread.join
    end
  ensure
    thread&.kill&.join
  end

  it 'blocks a counter trade once a stop placed first becomes active' do
    expect { run_stop }.to output(/Set stop order SELL \/ 995000\.0 \/ 0\.2/).to_stdout
    expect(private_client).to have_received(:send_parent_order).once

    active_stop = { 'parent_order_id' => 'JCO-stop', 'parent_order_type' => 'STOP', 'side' => 'SELL', 'size' => 0.2 }
    allow(private_client).to receive(:parent_orders).and_return([active_stop])

    expect { run_counter_trade }.to raise_error(Thor::Error, /Active protective stop.*JCO-stop/)
    expect(private_client).not_to have_received(:send_child_order)
  end

  it 'blocks a counter trade after a stop submission times out even when there are no active parent orders' do
    allow(private_client).to receive(:send_parent_order).and_raise(Timeout::Error)
    expect { run_stop }.to raise_error(Bitflyer::Cli::StopSubmission::Unverified, /communication error/)
    record = Dir.glob(File.join(@stop_state_directory, '[0-9a-f]' * 64)).fetch(0)

    expect { run_counter_trade }.to raise_error(Thor::Error, /unverified.*#{Regexp.escape(record)}/)
    expect(private_client).not_to have_received(:send_child_order)

    File.unlink(record)
    expect { run_counter_trade }.to output("Clear position SELL / 0.2\n").to_stdout
    expect(private_client).to have_received(:send_child_order).once
  end

  it 'allows a counter trade when stop acceptance is confirmed and there are no active parent orders' do
    expect { run_stop }.to output(/Set stop order/).to_stdout
    expect { run_counter_trade }.to output("Clear position SELL / 0.2\n").to_stdout
    expect(private_client).to have_received(:send_child_order).once
  end

  it 'blocks a stop placement while a counter trade submitted first remains unresolved' do
    expect { run_counter_trade }.to output("Clear position SELL / 0.2\n").to_stdout
    expect(private_client).to have_received(:send_child_order).once

    expect { run_stop }.to raise_error(Thor::Error, /counter trade offset.*unresolved/)
    expect(private_client).not_to have_received(:send_parent_order)
  end
end
