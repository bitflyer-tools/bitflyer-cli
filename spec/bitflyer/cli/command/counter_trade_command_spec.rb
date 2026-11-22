require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'timeout'

describe 'Loading the counter trade command on its own' do
  it 'submits an order for an open position without loading another command' do
    script = <<~'RUBY'
      require 'bitflyer/cli/command/counter_trade_command'

      client = Object.new
      def client.positions
        [{ 'side' => 'BUY', 'price' => 1_000_000, 'size' => 0.1 }]
      end

      def client.parent_orders(**)
        []
      end

      def client.send_child_order(product_code:, child_order_type:, side:, size:)
        Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, { 'child_order_acceptance_id' => 'accepted' })
      end

      def client.close
        puts 'Client closed'
      end

      Bitflyer::Cli::PersistentHTTPClient.define_singleton_method(:new) { |*, **| client }
      command = CounterTradeCommand.new
      command.run

      other_commands = $LOADED_FEATURES.grep(%r{/bitflyer/cli/command/(?!counter_trade_command\.rb\z)})
      abort "Loaded other commands: #{other_commands.join(', ')}" unless other_commands.empty?
    RUBY

    lib = File.expand_path('../../../../lib', __dir__)
    stdout, stderr, status = Dir.mktmpdir do |directory|
      env = { 'XDG_STATE_HOME' => directory, 'BITFLYER_API_KEY' => 'key', 'BITFLYER_API_SECRET' => 'secret' }
      Open3.capture3(env, RbConfig.ruby, '-I', lib, '-e', script)
    end

    expect(status.success?).to be(true), stdout + stderr
    expect(stdout).to eq("Clear position SELL / 0.1\nClient closed\n")
  end
end

describe CounterTradeCommand, :counter_trade_state do
  subject(:run_command) { described_class.new.run }

  let!(:private_client) { stub_persistent_client }
  let(:http_status) { 200 }
  let(:accepted) { { 'child_order_acceptance_id' => 'JRF20180101-000000-000001' } }

  before do
    stub_responses(private_client, positions: positions, parent_orders: [], send_child_order: Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(http_status, accepted))
  end

  include_examples 'rejects malformed position snapshots', :send_child_order
  include_examples 'rejects unrepresentable order sizes', :send_child_order

  context 'when the position lookup is rejected' do
    let(:positions) { { 'status' => -200, 'error_message' => 'Invalid API key' } }

    it 'reports the API error without constructing a position or sending an order' do
      expect(Position).not_to receive(:new)
      expect { described_class.new.run }
        .to raise_error(HasHTTPClient::PositionLookupFailed, /Failed to look up positions:.*-200.*Invalid API key/)
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

    it 'does not submit an order if syncing the submission directory fails' do
      directory = Bitflyer::Cli::CounterTradeSubmission.state_directory
      directory_handle = instance_double(File)
      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open).with(directory, File::RDONLY).and_yield(directory_handle)
      allow(directory_handle).to receive(:fsync).and_raise(Errno::EIO)

      expect { described_class.new.run }.to raise_error(Errno::EIO)
      expect(private_client).not_to have_received(:send_child_order)
    end

    it 'syncs every new directory entry before sending the first order' do
      root = Bitflyer::Cli::CounterTradeSubmission.state_directory
      parent = File.join(root, 'bitflyer-cli')
      directory = File.join(parent, 'counter-trades')
      parent_handle = instance_double(File, fsync: 0)
      root_handle = instance_double(File, fsync: 0)
      allow(Bitflyer::Cli::CounterTradeSubmission).to receive(:state_directory).and_return(directory)
      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open).with(parent, File::RDONLY).and_yield(parent_handle)
      allow(File).to receive(:open).with(root, File::RDONLY).and_yield(root_handle)
      allow(private_client).to receive(:send_child_order) do
        expect(parent_handle).to have_received(:fsync).once
        expect(root_handle).to have_received(:fsync).once
        Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(http_status, accepted)
      end

      expect { described_class.new.run }.to output("Clear position SELL / 0.3\n").to_stdout
    end
  end

  context 'when checking for active protective stops' do
    let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.2)] }
    let(:stop) do
      { 'id' => 1, 'parent_order_id' => 'JCO-stop', 'parent_order_type' => 'STOP', 'side' => 'SELL', 'size' => 0.2 }
    end

    it 'allows an offset when the active orders contain no protective stop for the position' do
      stub_responses(private_client, parent_orders: [stop.merge('side' => 'BUY'), { 'parent_order_type' => 'IFDOCO' }])

      expect { run_command }.to output("Clear position SELL / 0.2\n").to_stdout
      expect(private_client).to have_received(:send_child_order).once
    end

    it 'blocks even a smaller protective stop on a later page' do
      first_page = (2..101).map { |id| { 'id' => id, 'parent_order_type' => 'OCO' } }
      query = { product_code: 'FX_BTC_JPY', parent_order_state: 'ACTIVE', count: 100 }
      allow(private_client).to receive(:parent_orders).with(**query, before: nil).and_return(first_page)
      allow(private_client).to receive(:parent_orders).with(**query, before: 2).and_return([stop.merge('size' => 0.01)])

      expect { run_command }.to raise_error(Thor::Error, /Active protective stop.*JCO-stop/)
      expect(private_client).not_to have_received(:send_child_order)
    end

    it 'blocks when pagination cannot advance' do
      page = (1..100).map { |id| { 'id' => id, 'parent_order_type' => 'OCO' } }
      stub_responses(private_client, parent_orders: page)

      expect { run_command }.to raise_error(Thor::Error, /Could not paginate/)
      expect(private_client).not_to have_received(:send_child_order)
    end

    it 'includes the parent ID when a stop has an invalid side' do
      stub_responses(private_client, parent_orders: [stop.merge('side' => nil)])

      expect { run_command }.to raise_error(Thor::Error, /Could not verify active parent order.*JCO-stop/)
      expect(private_client).not_to have_received(:send_child_order)
    end

    it 'blocks when the list request times out' do
      allow(private_client).to receive(:parent_orders).and_raise(Net::ReadTimeout)

      expect { run_command }.to raise_error(Thor::Error, /Could not verify active protective stops/)
      expect(private_client).not_to have_received(:send_child_order)
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

  context 'when an offset might have been accepted' do
    let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.2)] }

    it 'retains an unverified record after a timeout' do
      allow(private_client).to receive(:send_child_order).and_raise(Net::ReadTimeout)

      expect { described_class.new.run }.to raise_error(Thor::Error, /communication error/)
      expect { described_class.new.run }.to raise_error(Thor::Error, /acceptance is unverified/)
      expect(private_client).to have_received(:send_child_order).once
    end

    context 'with a gateway error carrying an exchange error body' do
      let(:http_status) { 502 }
      let(:accepted) { { 'status' => -205 } }

      it 'requires reconciliation before retrying' do
        expect { described_class.new.run }.to raise_error(Thor::Error, /HTTP 502/)
        expect { described_class.new.run }.to raise_error(Thor::Error, /acceptance is unverified/)
        expect(private_client).to have_received(:send_child_order).once
      end
    end

    it 'blocks a second API key while the original order is pending' do
      expect { described_class.new.run }.to output(/Clear position/).to_stdout
      allow(ENV).to receive(:fetch).with('BITFLYER_API_KEY', nil).and_return('other-key')

      expect { described_class.new.run }.to raise_error(Thor::Error, /original API key/)
      expect(private_client).to have_received(:send_child_order).once
    end

    it 'keeps reconciling a completed offset after a failed position lookup' do
      acceptance_id = accepted.fetch('child_order_acceptance_id')
      completed = accepted.merge('child_order_state' => 'COMPLETED', 'executed_size' => 0.2)
      allow(private_client).to receive(:child_order_by_acceptance_id)
        .with(product_code: 'FX_BTC_JPY', child_order_acceptance_id: acceptance_id).and_return([completed])
      allow(private_client).to receive(:positions)
        .and_return(positions, { 'status' => -200, 'error_message' => 'Positions unavailable' }, [])

      expect { described_class.new.run }.to output(/Clear position/).to_stdout
      expect { described_class.new.run }
        .to raise_error(Thor::Error, /Could not confirm exposure after the previous counter trade:.*Positions unavailable/)
      expect { described_class.new.run }.to output("You don't have any position now.\n").to_stdout

      expect(private_client).to have_received(:child_order_by_acceptance_id).twice
      expect(private_client).to have_received(:send_child_order).once
    end
  end

end

describe 'Concurrent counter trades' do
  let(:script) do
    <<~'RUBY'
      require 'bitflyer/cli/command/counter_trade_command'

      $stdout.sync = true
      client = Object.new
      def client.positions
        return [] if ENV.fetch('PHASE') == 'visible'

        [{ 'side' => 'BUY', 'price' => 1_000_000, 'size' => 0.2 }]
      end

      def client.parent_orders(**)
        []
      end

      def client.send_child_order(product_code:, child_order_type:, side:, size:)
        File.open(ENV.fetch('ORDER_LOG'), 'a') { |log| log.puts "#{side} #{size}" }
        if ENV.fetch('PHASE') == 'first'
          puts 'Submitted'
          $stdin.gets
        end
        Bitflyer::Cli::PersistentHTTPClient::PostResponse.new(200, { 'child_order_acceptance_id' => 'accepted' })
      end

      def client.child_order_by_acceptance_id(product_code:, child_order_acceptance_id:)
        return [] if ENV.fetch('PHASE') == 'pending'

        [{ 'child_order_acceptance_id' => child_order_acceptance_id,
           'child_order_state' => 'COMPLETED', 'executed_size' => 0.2 }]
      end

      def client.close
        puts 'Client closed'
      end

      Bitflyer::Cli::PersistentHTTPClient.define_singleton_method(:new) { |*, **| client }
      command = CounterTradeCommand.new
      if ENV.fetch('PHASE') == 'pending'
        lock = File.join(Bitflyer::Cli::CounterTradeSubmission.state_directory, 'FX_BTC_JPY.json.lock')
        File.open(lock, 'r+') do |file|
          abort 'First process did not hold the lock' if file.flock(File::LOCK_EX | File::LOCK_NB)
        end
      end
      puts 'Ready'
      begin
        command.run
      rescue Thor::Error => e
        abort e.message
      end
    RUBY
  end

  it 'suppresses a concurrent offset and reconciles only after the fill is reflected in exposure' do
    lib = File.expand_path('../../../../lib', __dir__)
    Dir.mktmpdir do |directory|
      log = File.join(directory, 'orders')
      env = { 'XDG_STATE_HOME' => directory, 'ORDER_LOG' => log,
              'BITFLYER_API_KEY' => 'key', 'BITFLYER_API_SECRET' => 'secret' }
      command = [RbConfig.ruby, '-I', lib, '-e', script]

      Timeout.timeout(15) do
        Open3.popen3(env.merge('PHASE' => 'first'), *command) do |input, output, errors, first|
          expect(output.gets).to eq("Ready\n")
          expect(output.gets).to eq("Submitted\n")
          Open3.popen3(env.merge('PHASE' => 'pending'), *command) do |_, second_out, second_err, second|
            expect(second_out.gets).to eq("Ready\n")
            input.puts 'Continue'
            expect(first.value).to be_success, errors.read
            expect(output.read).to eq("Clear position SELL / 0.2\nClient closed\n")
            expect(second.value.exitstatus).to eq(1)
            expect(second_out.read).to eq("Client closed\n")
            expect(second_err.read).to include('awaiting reconciliation')
          ensure
            input.close
          end
        end

        stdout, stderr, status = Open3.capture3(env.merge('PHASE' => 'stale'), *command)
        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq("Ready\nClient closed\n")
        expect(stderr).to include('exposure is not confirmed')

        stdout, stderr, status = Open3.capture3(env.merge('PHASE' => 'visible'), *command)
        expect(status).to be_success, stderr
        expect(stdout).to eq("Ready\nYou don't have any position now.\nClient closed\n")
        expect(File.readlines(log)).to eq(["SELL 0.2\n"])
      end
    end
  end
end
