require 'spec_helper'
require 'timeout'

describe StopByRangeCommand, :stop_state do
  subject(:run_command) { run }

  let!(:private_client) { stub_private_client }
  let(:response) { { 'parent_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(private_client, positions: positions, parent_orders: [], send_parent_order: response)
  end

  include_examples 'rejects malformed position snapshots', :send_parent_order
  include_examples 'rejects unrepresentable order sizes', :send_parent_order

  def run(range = 5000)
    described_class.new.run(thor_options(range: range))
  end

  def stop_order(side:, trigger_price:, size:)
    {
      order_method: 'SIMPLE',
      parameters: [{ product_code: 'FX_BTC_JPY', condition_type: 'STOP', side: side, trigger_price: trigger_price,
                     size: size }]
    }
  end

  context 'without any position' do
    let(:positions) { [] }

    it 'does not send an order' do
      expect { run }.to output("You don't have any position now.\n").to_stdout
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end

  context 'when the position lookup is rejected' do
    let(:positions) { { 'status' => -200 } }

    it 'reports the API status without constructing a position or sending an order' do
      expect(Position).not_to receive(:new)
      expect { run }
        .to raise_error(HasHTTPClient::PositionLookupFailed, /Failed to look up positions:.*-200/)
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end

  context 'with a long position' do
    let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.2)] }

    [0, -5000].each do |range|
      it "rejects a range of #{range} without sending an order" do
        expect { run(range) }.to raise_error(ArgumentError, 'Range must be positive')
        expect(private_client).not_to have_received(:send_parent_order)
      end
    end

    it 'sets a sell stop below the average price' do
      expect { run }.to output("Set stop order SELL / 995000.0 / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_parent_order)
        .with(stop_order(side: 'SELL', trigger_price: 995_000.0, size: 0.2))
    end

    it 'submits only once when another invocation starts before acceptance is visible' do
      first = second = nil
      posting = Queue.new
      continue_post = Queue.new
      second_position = Queue.new
      allow(private_client).to receive(:positions) do
        second_position << true if Thread.current[:second_stop_run]
        positions
      end
      allow(private_client).to receive(:send_parent_order) do
        if !Thread.current[:second_stop_run]
          posting << true
          continue_post.pop
        end
        response
      end

      expect do
        Timeout.timeout(5) do
          first = Thread.new { run }
          posting.pop
          second = Thread.new do
            Thread.current[:second_stop_run] = true
            run
          end
          second_position.pop
          continue_post << true
          [first, second].each(&:value)
        end
      end.to output(/Set stop order.*awaiting confirmation/m).to_stdout
      expect(private_client).to have_received(:send_parent_order).once
    ensure
      [first, second].compact.each { |thread| thread.kill.join }
    end

    it 'allows replacement after the accepted stop is canceled' do
      expect { run }.to output(/Set stop order/).to_stdout
      allow(private_client).to receive(:parent_orders)
        .with(hash_including(parent_order_state: 'CANCELED')).and_return([response])

      expect { run }.to output(/Set stop order/).to_stdout
      expect(private_client).to have_received(:send_parent_order).twice
    end

    it 'does not replace a completed stop using the current position snapshot' do
      expect { run }.to output(/Set stop order/).to_stdout
      allow(private_client).to receive(:parent_orders)
        .with(hash_including(parent_order_state: 'COMPLETED')).and_return([response])

      expect { run }.to output(/Previous stop order.*COMPLETED/).to_stdout
      expect(private_client).to have_received(:send_parent_order).once
    end

    it 'allows stops with different parameters while acceptance is pending' do
      expect { run }.to output(/Set stop order/).to_stdout
      expect { run(6000) }.to output(/Set stop order SELL \/ 994000/).to_stdout
      expect(private_client).to have_received(:send_parent_order).twice
    end

    it 'keeps the stop pending after a transport failure' do
      allow(private_client).to receive(:send_parent_order).and_raise(Timeout::Error)
      expect { run }.to raise_error(Timeout::Error)

      expect { run }.to output(/unverified.*awaiting confirmation/).to_stdout
      expect(private_client).to have_received(:send_parent_order).once
    end

    context 'with active parent orders' do
      let(:parent) { { 'id' => 1, 'parent_order_id' => 'JCO-stop', 'parent_order_type' => 'STOP' } }
      let(:parameters) do
        {
          'product_code' => 'FX_BTC_JPY', 'condition_type' => 'STOP', 'side' => 'SELL',
          'trigger_price' => 995_000, 'size' => 0.2, 'price' => 0, 'offset' => 0
        }
      end

      def stub_parent_detail(method: 'SIMPLE', parameters: [self.parameters])
        stub_responses(private_client, parent_order: { 'order_method' => method, 'parameters' => parameters })
      end

      it 'submits once and reports the existing stop on the next invocation' do
        expect { run }.to output(/Set stop order/).to_stdout
        stub_responses(private_client, parent_orders: [parent.merge(response)])
        stub_parent_detail

        expect { run }.to output("Existing stop order SELL / 995000.0 / 0.2 (JCO-stop)\n").to_stdout
        expect(private_client).to have_received(:parent_orders)
          .with(product_code: 'FX_BTC_JPY', parent_order_state: 'ACTIVE', count: 100, before: nil).twice
        expect(private_client).to have_received(:parent_order).with(parent_order_id: 'JCO-stop')
        expect(private_client).to have_received(:send_parent_order).once

        stub_responses(private_client, parent_orders: [])
        expect { run }.to output(/Set stop order/).to_stdout
        expect(private_client).to have_received(:send_parent_order).twice
      end

      it 'checks subsequent pages for a matching stop' do
        first_page = (2..101).map { |id| { 'id' => id, 'parent_order_type' => 'OCO' } }
        allow(private_client).to receive(:parent_orders).with(hash_including(before: nil)).and_return(first_page)
        allow(private_client).to receive(:parent_orders).with(hash_including(before: 2)).and_return([parent])
        stub_parent_detail

        expect { run }.to output(/Existing stop order.*JCO-stop/).to_stdout
        expect(private_client).not_to have_received(:send_parent_order)
      end

      {
        'product_code' => 'BTC_JPY', 'condition_type' => 'STOP_LIMIT', 'side' => 'BUY',
        'trigger_price' => 994_000, 'size' => 0.1
      }.each do |key, value|
        it "submits a stop when the active order has a different #{key}" do
          stub_responses(private_client, parent_orders: [parent])
          stub_parent_detail(parameters: [parameters.merge(key => value)])

          expect { run }.to output(/Set stop order/).to_stdout
          expect(private_client).to have_received(:send_parent_order).once
        end
      end

      it 'submits a stop when the matching leg belongs to a linked strategy' do
        stub_responses(private_client, parent_orders: [parent.merge('parent_order_type' => 'OCO')])

        expect { run }.to output(/Set stop order/).to_stdout
        expect(private_client).to have_received(:send_parent_order).once
      end

      it 'aborts without submitting when the active order list is unavailable' do
        stub_responses(private_client, parent_orders: { 'status' => -200 })

        expect { run }.to raise_error(StopByRangeCommand::LookupFailed, /active parent orders/)
        expect(private_client).not_to have_received(:send_parent_order)
      end

      it 'aborts without submitting when the stop details are unavailable' do
        stub_responses(private_client, parent_orders: [parent], parent_order: { 'status' => -200 })

        expect { run }.to raise_error(StopByRangeCommand::LookupFailed, /JCO-stop/)
        expect(private_client).not_to have_received(:send_parent_order)
      end
    end

    context 'when the stop order is rejected' do
      let(:response) { { 'status' => -200, 'error_message' => 'Order rejected' } }

      it 'raises with the exchange rejection' do
        expect { run }.to raise_error(Bitflyer::Cli::OrderRejected, 'Order rejected')
        stub_responses(private_client, send_parent_order: { 'parent_order_acceptance_id' => 'accepted' })
        expect { run }.to output(/Set stop order/).to_stdout
      end
    end
  end

  context 'with a short position' do
    let(:positions) { [position(side: 'SELL', price: '1e6', size: '0.2')] }

    it 'sets a buy stop above the average price' do
      expect { run }.to output("Set stop order BUY / 1005000.0 / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_parent_order)
        .with(stop_order(side: 'BUY', trigger_price: 1_005_000.0, size: 0.2))
    end
  end

  context 'with a net long position' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.3), position(side: 'SELL', price: 1_100_000, size: 0.1)]
    end

    it 'sets a sell stop below the net entry price' do
      expect { run }.to output("Set stop order SELL / 945000.0 / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_parent_order)
        .with(stop_order(side: 'SELL', trigger_price: 945_000.0, size: 0.2))
    end
  end

  context 'with offsetting positions' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.1), position(side: 'SELL', price: 1_100_000, size: 0.1)]
    end

    it 'does not send an order' do
      expect { run }.to output("You don't have any position now.\n").to_stdout
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end
end
