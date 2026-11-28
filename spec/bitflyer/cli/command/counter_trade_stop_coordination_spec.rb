# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

describe 'Coordinating protective stops with counter trades', :stop_state, :counter_trade_state do
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

  context 'with ten pages of active parent orders' do
    let(:last_page) { parent_order_page(100) }

    before do
      allow(private_client).to receive(:parent_orders) do |parent_order_state:, count:, before:, product_code:|
        expect([parent_order_state, count, product_code]).to eq(['ACTIVE', 100, 'FX_BTC_JPY'])
        highest_id = before ? before - 1 : 1000
        highest_id == 100 ? last_page : parent_order_page(highest_id)
      end
    end

    def parent_order_page(highest_id)
      highest_id.downto(highest_id - 99).map { |id| { 'id' => id, 'parent_order_type' => 'IFDOCO' } }
    end

    { run_stop: StopByRangeCommand::LookupFailed, run_counter_trade: Thor::Error }.each do |command, error|
      it "blocks #{command} after ten full pages and releases the product lock" do
        expect { public_send(command) }.to raise_error(error, /limit of 10 page requests/)
        expect(private_client).to have_received(:parent_orders).exactly(10).times
        expect(private_client).not_to have_received(:send_child_order)
        expect(private_client).not_to have_received(:send_parent_order)

        lock_path = File.join(Bitflyer::Cli::CounterTradeSubmission.state_directory, 'FX_BTC_JPY.json.lock')
        File.open(lock_path, 'r+') do |file|
          expect(file.flock(File::LOCK_EX | File::LOCK_NB)).to eq(0)
        end
      end
    end

    context 'when the last allowed page is short' do
      let(:last_page) { super().take(1) }

      it 'submits the stop after completing the scan' do
        expect { run_stop }.to output(/Set stop order/).to_stdout
        expect(private_client).to have_received(:parent_orders).exactly(10).times
        expect(private_client).to have_received(:send_parent_order).once
      end
    end

    context 'when the last allowed full page contains a protective stop' do
      let(:last_page) do
        super().tap { |page| page.last.merge!('parent_order_type' => 'STOP', 'side' => 'SELL', 'parent_order_id' => 'JCO-stop') }
      end

      it 'reports the matching stop' do
        expect { run_counter_trade }.to raise_error(Thor::Error, /Active protective stop.*JCO-stop/)
        expect(private_client).to have_received(:parent_orders).exactly(10).times
        expect(private_client).not_to have_received(:send_child_order)
      end
    end
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

  it 'blocks a stop placement while a counter trade submitted first remains unresolved' do
    expect { run_counter_trade }.to output("Clear position SELL / 0.2\n").to_stdout
    expect(private_client).to have_received(:send_child_order).once

    expect { run_stop }.to raise_error(Thor::Error, /counter trade offset.*unresolved/)
    expect(private_client).not_to have_received(:send_parent_order)
  end
end
