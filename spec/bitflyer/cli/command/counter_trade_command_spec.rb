require 'spec_helper'
require 'open3'
require 'rbconfig'

describe 'Loading the counter trade command on its own' do
  it 'submits an order for an open position without loading another command' do
    script = <<~'RUBY'
      $LOADED_FEATURES << 'bitflyer.rb'
      require 'bitflyer/cli/command/counter_trade_command'

      client = Object.new
      def client.positions
        [{ 'side' => 'BUY', 'price' => 1_000_000, 'size' => 0.1 }]
      end

      def client.send_child_order(product_code:, child_order_type:, side:, size:)
        { 'child_order_acceptance_id' => 'accepted' }
      end

      command = CounterTradeCommand.new
      command.define_singleton_method(:http_private_client) { client }
      command.run

      other_commands = $LOADED_FEATURES.grep(%r{/bitflyer/cli/command/(?!counter_trade_command\.rb\z)})
      abort "Loaded other commands: #{other_commands.join(', ')}" unless other_commands.empty?
    RUBY

    lib = File.expand_path('../../../../lib', __dir__)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-I', lib, '-e', script)

    expect(status.success?).to be(true), stdout + stderr
    expect(stdout).to eq("Clear position SELL / 0.1\n")
  end
end

describe CounterTradeCommand do
  subject(:run_command) { described_class.new.run }

  let!(:private_client) { stub_private_client }
  let(:accepted) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(private_client, positions: positions, send_child_order: accepted)
  end

  include_examples 'rejects malformed position snapshots', :send_child_order
  include_examples 'rejects unrepresentable order sizes', :send_child_order

  context 'when the position lookup is rejected' do
    let(:positions) { { 'status' => -200, 'error_message' => 'Invalid API key' } }

    it 'reports the API error without constructing a position or sending an order' do
      expect(Position).not_to receive(:new)
      expect { described_class.new.run }.to output(/Failed to look up positions:.*-200.*Invalid API key/).to_stderr
      expect(private_client).not_to have_received(:send_child_order)
    end
  end

  context 'with no positions' do
    let(:positions) { [] }

    it 'prints a message without submitting an order' do
      expect { described_class.new.run }.to output("You don't have any position now.\n").to_stdout
      expect(private_client).not_to have_received(:send_child_order)
    end
  end

  context 'with a flat net position' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.1), position(side: 'SELL', price: 1_100_000, size: 0.1)]
    end

    it 'reports the flat net position without submitting an order' do
      expect { described_class.new.run }.to output("Your net position is already flat.\n").to_stdout
      expect(private_client).not_to have_received(:send_child_order)
    end
  end

  context 'with a long position' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.1), position(side: 'BUY', price: 1_000_000, size: 0.2)]
    end

    it 'sells the whole position at market' do
      expect { described_class.new.run }.to output("Clear position SELL / 0.3\n").to_stdout
      expect(private_client).to have_received(:send_child_order)
        .with(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'SELL', size: 0.3)
    end
  end

  context 'with a net short position' do
    let(:positions) do
      [position(side: 'SELL', price: '1e6', size: '0.6'), position(side: 'BUY', price: 1_100_000, size: 0.1)]
    end

    it 'buys the net position at market' do
      expect { described_class.new.run }.to output("Clear position BUY / 0.5\n").to_stdout
      expect(private_client).to have_received(:send_child_order)
        .with(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY', size: 0.5)
    end
  end

  context 'when the order is rejected' do
    let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.1)] }
    let(:accepted) { { 'status' => -205 } }

    it 'raises with the exchange rejection' do
      expect { described_class.new.run }.to raise_error(Bitflyer::Cli::OrderRejected, /Order rejected:.*-205/)
    end
  end
end
