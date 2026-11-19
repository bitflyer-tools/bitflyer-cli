require 'spec_helper'

describe 'bitflyer executable' do
  let(:private_client) { stub_private_client }

  def run_executable(*args)
    stub_const('ARGV', args)
    load File.expand_path('../../exe/bitflyer', __dir__)
  end

  it 'prints a cancel-all rejection to stderr and exits unsuccessfully' do
    stub_responses(private_client, cancel_all_child_orders: { 'status' => -200, 'error_message' => 'rejected' })

    expect do
      expect { run_executable('cancel_all') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("rejected\n").to_stderr
  end

  it 'completes normally when the cancellation is accepted' do
    stub_responses(private_client, cancel_all_child_orders: '')

    expect { run_executable('cancel_all') }.to output('').to_stderr
  end

  {
    %w[counter_trade] => 'child',
    %w[order_by_best --amount=0.01 --type=buy] => 'child',
    %w[stop_by_range --range=5000] => 'parent',
    %w[ifdoco_by_range --amount=0.01 --type=buy --range=10000 --percentage=60] => 'parent'
  }.each do |args, order_type|
    context "when running #{args.first}" do
      let(:order_method) { :"send_#{order_type}_order" }

      before do
        stub_responses(private_client, positions: [position(side: 'BUY', price: 1_000_000, size: 0.1)])
        stub_responses(stub_public_client, ticker: { 'best_bid' => 1_000_000, 'ltp' => 1_000_000 })
      end

      it 'prints the exchange rejection to stderr and exits unsuccessfully' do
        stub_responses(private_client, order_method => { 'status' => -205, 'error_message' => 'Insufficient margin' })

        expect do
          expect { run_executable(*args) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        end.to output("Insufficient margin\n").to_stderr.and output('').to_stdout
      end

      it 'completes normally when the order is accepted' do
        stub_responses(private_client, order_method => { "#{order_type}_order_acceptance_id" => 'accepted' })

        expect { run_executable(*args) }.to output('').to_stderr.and output(/.+/).to_stdout
        expect(private_client).to have_received(order_method)
      end
    end
  end
end
