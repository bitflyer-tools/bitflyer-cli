require 'spec_helper'
require 'timeout'

describe StopByRangeCommand, :stop_state do
  subject(:run_command) { run }

  let!(:private_client) { stub_persistent_client }
  let(:response) { { 'parent_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(private_client, positions: positions, parent_orders: [], send_parent_order: post_response)
  end

  include_examples 'rejects malformed position snapshots', :send_parent_order
  include_examples 'rejects unrepresentable order sizes', :send_parent_order

  def run(range = 5000)
    described_class.new.run(thor_options(range: range))
  end

  def post_response(status = 200, body = response)
    Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(status, body)
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

    [999_999.5, 1_000_000, 1_200_000].each do |range|
      it "rejects a nonpositive sell stop trigger from a range of #{range}" do
        expect { run(range) }.to raise_error(Thor::Error, 'Stop trigger price must be positive and finite.')
        expect(private_client).not_to have_received(:parent_orders)
        expect(private_client).not_to have_received(:send_parent_order)
      end
    end

    it 'sets a sell stop below the average price' do
      expect { run }.to output("Set stop order SELL / 995000.0 / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_parent_order)
        .with(stop_order(side: 'SELL', trigger_price: 995_000.0, size: 0.2)).once
    end

    it 'does not submit when an external stop closes the position during active-order lookup' do
      allow(private_client).to receive(:parent_orders).with(hash_including(parent_order_state: 'ACTIVE')) do
        stub_responses(private_client, positions: [])
        []
      end

      expect { run }.to output("You don't have any position now.\n").to_stdout
      expect(private_client).not_to have_received(:send_parent_order)
    end

    it 'does not replace a canceled stop when the position changes during reconciliation' do
      expect { run }.to output(/Set stop order/).to_stdout
      reduced_positions = [position(side: 'BUY', price: 1_000_000, size: 0.1)]
      allow(private_client).to receive(:parent_orders).with(hash_including(parent_order_state: 'CANCELED')) do
        stub_responses(private_client, positions: reduced_positions)
        [response]
      end

      expect { run }.to raise_error(StopByRangeCommand::LookupFailed, /Position changed/)
      expect(private_client).to have_received(:send_parent_order).once
    end

    it 'aborts when the refreshed position requires a different stop' do
      reduced_positions = [position(side: 'BUY', price: 1_000_000, size: 0.1)]
      allow(private_client).to receive(:positions).and_return(positions, reduced_positions)

      expect { run }.to raise_error(StopByRangeCommand::LookupFailed, /Position changed/)
      expect(private_client).not_to have_received(:send_parent_order)
    end

    it 'rejects a nonpositive trigger from the refreshed position' do
      refreshed_positions = [position(side: 'BUY', price: 5000, size: 0.2)]
      allow(private_client).to receive(:positions).and_return(positions, refreshed_positions)

      expect { run }.to raise_error(Thor::Error, 'Stop trigger price must be positive and finite.')
      expect(private_client).not_to have_received(:parent_orders)
      expect(private_client).not_to have_received(:send_parent_order)
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
        post_response
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

    it 'does not replace a completed stop across two runs with the same stale position' do
      expect { run }.to output(/Set stop order/).to_stdout
      allow(private_client).to receive(:parent_orders)
        .with(hash_including(parent_order_state: 'COMPLETED')).and_return([response], [])

      2.times do
        expect { run }.to output(/Previous stop order.*#{response.values.first}.*COMPLETED/).to_stdout
      end
      expect(private_client).to have_received(:send_parent_order).once
    end

    it 'does not resubmit when the position disappears while another invocation checks completion' do
      first = second = nil
      checking_completion = Queue.new
      second_snapshot = Queue.new
      expect { run }.to output(/Set stop order/).to_stdout
      stale_positions = positions
      allow(private_client).to receive(:positions) do
        next stale_positions unless Thread.current[:second_stop_run]
        next [] if Thread.current[:read_stop_position]

        Thread.current[:read_stop_position] = true
        second_snapshot << true
        stale_positions
      end
      allow(private_client).to receive(:parent_orders).with(hash_including(parent_order_state: 'COMPLETED')) do
        checking_completion << true
        second_snapshot.pop
        [response]
      end

      expect do
        Timeout.timeout(5) do
          first = Thread.new { run }
          checking_completion.pop
          second = Thread.new do
            Thread.current[:second_stop_run] = true
            run
          end
          [first, second].each(&:value)
        end
      end.to output(/Previous stop order.*COMPLETED.*You don't have any position now\./m).to_stdout
      expect(private_client).to have_received(:send_parent_order).once
    ensure
      [first, second].compact.each { |thread| thread.kill.join }
    end

    it 'allows stops with different parameters while acceptance is pending' do
      expect { run }.to output(/Set stop order/).to_stdout
      expect { run(6000) }.to output(/Set stop order SELL \/ 994000/).to_stdout
      expect(private_client).to have_received(:send_parent_order).twice
    end

    it 'keeps the stop pending after a transport failure' do
      allow(private_client).to receive(:send_parent_order).and_raise(Timeout::Error)
      expect { run }.to raise_error(Bitflyer::Cli::StopSubmission::Unverified, /communication error/)

      expect { run }.to raise_error(Bitflyer::Cli::StopSubmission::Unverified, /unverified.*awaiting confirmation/)
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
        allow(private_client).to receive(:parent_orders)
          .with(hash_including(parent_order_state: 'CANCELED')).and_return([response])
        expect { run }.to output(/Set stop order/).to_stdout
        expect(private_client).to have_received(:send_parent_order).twice
      end

      it 'remembers the acceptance ID after the stop becomes active and then completes' do
        expect { run }.to output(/Set stop order/).to_stdout
        allow(private_client).to receive(:parent_orders)
          .with(hash_including(parent_order_state: 'ACTIVE')).and_return([parent.merge(response)], [])
        stub_parent_detail

        expect { run }.to output(/Existing stop order/).to_stdout
        allow(private_client).to receive(:parent_orders)
          .with(hash_including(parent_order_state: 'COMPLETED')).and_return([response])
        expect { run }.to output(/Previous stop order.*COMPLETED/).to_stdout
        expect(private_client).to have_received(:send_parent_order).once
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
      before do
        stub_responses(private_client, send_parent_order: post_response(400, {
                         'status' => -200, 'error_message' => 'Order rejected'
                       }))
      end

      it 'raises with the exchange rejection' do
        expect { run }.to raise_error(Bitflyer::Cli::OrderRejected, 'Order rejected')
        stub_responses(private_client, send_parent_order: post_response)
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

    it 'rejects an infinite buy stop trigger' do
      expect { run(Float::INFINITY) }.to raise_error(Thor::Error, 'Stop trigger price must be positive and finite.')
      expect(private_client).not_to have_received(:parent_orders)
      expect(private_client).not_to have_received(:send_parent_order)
    end
  end

  context 'with a fractional short break-even price' do
    let(:positions) do
      [position(side: 'SELL', price: 10_000, size: 0.01), position(side: 'SELL', price: 10_001, size: 0.03)]
    end
    let(:buy_stop) { stop_order(side: 'BUY', trigger_price: 10_002, size: 0.04) }

    it 'adds the range to 10,000.75 yen before rounding the buy trigger up' do
      expect { run(0.5) }.to output(/Set stop order BUY/).to_stdout
      expect(private_client).to have_received(:send_parent_order).with(buy_stop)
    end

    it 'recognizes an active stop at the final trigger price' do
      parent = { 'id' => 1, 'parent_order_id' => 'JCO-stop', 'parent_order_type' => 'STOP' }
      parameters = buy_stop.fetch(:parameters).map { |parameter| parameter.transform_keys(&:to_s) }
      stub_responses(private_client, parent_orders: [parent],
                                     parent_order: { 'order_method' => 'SIMPLE', 'parameters' => parameters })

      expect { run(0.5) }.to output(/Existing stop order BUY.*JCO-stop/).to_stdout
      expect(private_client).not_to have_received(:send_parent_order)
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
