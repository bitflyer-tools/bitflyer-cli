require 'spec_helper'
require 'timeout'

describe SummaryCommand do
  let!(:private_client) { stub_persistent_client }
  let!(:realtime_client) { stub_realtime_client }
  let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.1)] }
  let(:executions_callback) { [] }
  let(:disconnect_callback) { [] }
  let(:opening_executions) { [] }

  before do
    stub_responses(private_client, positions: positions, collateral: { 'collateral' => 50_000 })
    allow(realtime_client).to receive(:executions_fx_btc_jpy=) do |callback|
      executions_callback << callback
      opening_executions.shift(opening_executions.size).each { |batch| callback.call(batch) }
    end
    allow(realtime_client).to receive(:disconnected=) { |callback| disconnect_callback << callback }
  end

  def run_once(command)
    run_iterations(command)
  end

  context 'when the initial position lookup is rejected' do
    let(:positions) { { 'status' => -200, 'error_message' => 'Invalid API key' } }

    it 'reports the API error and skips account rendering' do
      expect(Position).not_to receive(:new)
      expect(Thread).not_to receive(:new)
      expect(Bitflyer::Cli::RealtimeClient).not_to receive(:new)
      expect { described_class.new.run }
        .to raise_error(HasHTTPClient::PositionLookupFailed, /Failed to look up positions:.*-200.*Invalid API key/)
      expect(private_client).not_to have_received(:collateral)
      expect(private_client).to have_received(:close).once
    end
  end

  context 'without any position' do
    let(:positions) { [] }

    it 'renders the empty position' do
      output = capture_stdout { run_once(described_class.new) }

      expect(output).to include('Position: 0 * 0.0')
    end
  end

  context 'with an invalid collateral response' do
    {
      'a rejected response' => [{ 'status' => -1, 'error_message' => 'Collateral unavailable' }, /-1.*Collateral unavailable/],
      'a rejected response with collateral' => [{ 'status' => -1, 'collateral' => 60_000 }, /-1/],
      'a missing value' => [{}, /\{\}/],
      'a null value' => [{ 'collateral' => nil }, /nil/]
    }.each do |description, (response, details)|
      context "with #{description}" do
        let(:error) { /Failed to look up collateral:.*#{details}/ }

        it 'reports the startup failure and skips the feed and balance rendering' do
          stub_responses(private_client, collateral: response)
          expect(Thread).not_to receive(:new)
          expect(Bitflyer::Cli::RealtimeClient).not_to receive(:new)

          expect { described_class.new.run }.to raise_error(HasHTTPClient::AccountLookupFailed, error)
          expect(private_client).to have_received(:close).once
        end

        it 'reports the refresh failure and marks both previous account figures as stale' do
          command = described_class.new
          opening_executions << [{ 'price' => 2_000_000 }]
          stub_responses(
            private_client,
            positions: [position(side: 'BUY', price: 2_000_000, size: 0.2)],
            collateral: response
          )

          expect { command.send(:update_balance) }.to output(error).to_stderr
          output = capture_stdout { run_once(command) }
          expect(output).to include('Position: 1,000,000 * 0.1', 'Balance:  150,000', '[stale]')
        end
      end
    end
  end

  it 'renders a balance of zero when the collateral lookup succeeds with zero' do
    stub_responses(private_client, collateral: { 'collateral' => 0 })
    command = described_class.new
    opening_executions << [{ 'price' => 1_000_000 }]

    expect(capture_stdout { run_once(command) }).to match(/Balance:  0 +\(/)
  end

  it 'reports a rejected refresh and shows saved account data as stale until a successful refresh' do
    command = described_class.new
    stub_responses(private_client, positions: { 'status' => -200 })
    allow(Thread).to receive(:new).and_yield
    expect(command).to receive(:sleep).with(5).ordered
    expect(command).to receive(:sleep).with(5).ordered.and_raise(Interrupt)
    expect { capture_stdout { command.run } }.to output(/Failed to look up positions:.*-200/).to_stderr
    expect(private_client).to have_received(:collateral).once
    opening_executions << [{ 'price' => 1_000_000 }]
    refresh = -> { refresh_account(command, price: 1_000_000, size: 0.2, collateral: 60_000) }
    stale, recovered = capture_stdout { run_iterations(command, refresh) }.split("\e[4F\e[0J").drop(1)

    expect(stale).to include('Current:  1,000,000', 'Position: 1,000,000 * 0.1', 'Balance:  50,000', '[stale]')
    expect(recovered).to include('Position: 1,000,000 * 0.2', 'Balance:  60,000')
    expect(recovered).not_to include('[stale]')
  end

  it 'loads the account once at startup and waits five seconds between refreshes' do
    expect(private_client).to receive(:positions).ordered
    expect(private_client).to receive(:collateral).ordered
    command = described_class.new

    allow(Thread).to receive(:new).and_yield
    expect(command).to receive(:sleep).with(5).ordered
    expect(private_client).to receive(:positions).ordered
    expect(private_client).to receive(:collateral).ordered
    expect(command).to receive(:sleep).with(5).ordered.and_raise(Interrupt)

    capture_stdout { command.run }
  end

  it 'prints the current price, spread and balance with profit' do
    command = described_class.new
    opening_executions << [{ 'price' => 1_005_000 }, { 'price' => 1_010_000 }]

    output = capture_stdout { run_once(command) }

    expect(output).to include('Current:  1,010,000', 'Position: 1,000,000 * 0.1', 'Balance:  51,000')
    expect(output).to include("Spread:   +\e[0;32;49m10,000\e[0m", "(+\e[0;32;49m1,000\e[0m)")
  end

  it 'renders a negative spread and loss in red' do
    command = described_class.new
    opening_executions << [{ 'price' => 990_000 }]

    output = capture_stdout { run_once(command) }

    expect(output).to include("Spread:   \e[0;31;49m-10,000\e[0m")
    expect(output).to include("Balance:  #{'49,000'.ljust(15)} (\e[0;31;49m-1,000\e[0m)")
  end

  it 'keeps the last complete account data until a scheduled refresh succeeds' do
    command = described_class.new
    execution = [{ 'price' => 1_000_000 }]
    opening_executions << execution
    new_positions = [position(side: 'BUY', price: 1_100_000, size: 0.2)]
    expect(private_client).to receive(:positions).ordered.and_return(new_positions)
    expect(private_client).to receive(:collateral).ordered.and_raise(IOError)
    expect(private_client).to receive(:positions).ordered.and_return(new_positions)
    expect(private_client).to receive(:collateral).ordered.and_return('collateral' => 60_000)

    poller = nil
    allow(Thread).to receive(:new) do |&poll|
      poller = Fiber.new(&poll)
      poller.resume
      instance_double(Thread, kill: nil, join: nil)
    end
    allow(command).to receive(:sleep).with(5) { Fiber.yield }
    expect(command).to receive(:sleep).with(0.1).exactly(5).times.and_invoke(
      ->(_) { poller.resume },
      ->(_) { disconnect_callback.last.call(nil) },
      ->(_) { poller.resume },
      ->(_) { executions_callback.last.call(execution) },
      ->(_) { raise Interrupt }
    )

    initial, stale, disconnected, refreshed, recovered = capture_stdout { command.run }.split("\e[4F\e[0J").drop(1)
    expect(initial).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000')
    expect(initial).not_to include('[stale]')
    expect(stale).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000', '[stale]')
    expect(disconnected).to include('Current:  Stale', 'Balance:  N/A (N/A) [stale]')
    expect(refreshed).to include('Position: 1,100,000 * 0.2', 'Balance:  N/A (N/A)')
    expect(refreshed).not_to include('[stale]')
    expect(recovered).to include('Position: 1,100,000 * 0.2', 'Balance:  40,000')
    expect(recovered).not_to include('[stale]')
  end

  it 'shows the previous account snapshot until collateral arrives' do
    command = described_class.new
    opening_executions << [{ 'price' => 2_000_000 }]
    collateral_started = Queue.new
    release_collateral = Queue.new
    allow(private_client).to receive(:positions).and_return([position(side: 'BUY', price: 2_000_000, size: 0.2)])
    allow(private_client).to receive(:collateral) do
      collateral_started << true
      release_collateral.pop
      { 'collateral' => 60_000 }
    end

    refresh = Thread.new { command.send(:update_balance) }
    Timeout.timeout(5) { collateral_started.pop }
    output = capture_stdout { run_once(command) }
    expect(output).to include('Position: 1,000,000 * 0.1', 'Balance:  150,000')

    opening_executions << [{ 'price' => 2_000_000 }]
    release_collateral << true
    Timeout.timeout(5) { refresh.value }
    output = capture_stdout { run_once(command) }
    expect(output).to include('Position: 2,000,000 * 0.2', 'Balance:  60,000')
  ensure
    refresh&.kill
    refresh&.join
  end

  it 'keeps the previous account snapshot when fetching collateral fails' do
    command = described_class.new
    opening_executions << [{ 'price' => 2_000_000 }]
    allow(private_client).to receive(:positions).and_return([position(side: 'BUY', price: 2_000_000, size: 0.2)])
    allow(private_client).to receive(:collateral).and_raise(IOError, 'Collateral request failed')

    expect { command.send(:update_balance) }.to raise_error(IOError, 'Collateral request failed')
    output = capture_stdout { run_once(command) }
    expect(output).to include('Position: 1,000,000 * 0.1', 'Balance:  150,000')
  end

  it 'uses the same price for the entire frame when an execution arrives during rendering' do
    account_position = Position.new(positions)
    allow(Position).to receive(:new).with(positions).and_return(account_position)
    command = described_class.new
    opening_executions << [{ 'price' => 1_010_000 }]
    allow(account_position).to receive(:profit).and_wrap_original do |original, price|
      executions_callback.last.call([{ 'price' => 1_020_000 }])
      original.call(price)
    end

    output = capture_stdout { run_once(command) }

    expect(output).to include('Current:  1,010,000')
    expect(output).to match(/Spread:   \+.*10,000/).and match(/Balance:  51,000 +\(\+.*1,000/)
  end

  it 'shows no profit before any execution arrives' do
    output = capture_stdout { run_once(described_class.new) }

    expect(output).to include('Current:  Stale', 'Spread:   N/A', 'Balance:  N/A (N/A)')
  end

  {
    'missing' => {},
    'empty' => { 'price' => '' },
    'nonnumeric' => { 'price' => 'invalid' },
    'partially numeric' => { 'price' => '1010000invalid' },
    'zero' => { 'price' => 0 },
    'negative' => { 'price' => -1 },
    'NaN' => { 'price' => Float::NAN },
    'infinite' => { 'price' => Float::INFINITY },
    'overflowing' => { 'price' => '1e999' }
  }.each do |description, invalid_execution|
    it "ignores a #{description} execution price without renewing the last valid price" do
      command = described_class.new
      allow(command).to receive(:monotonic_time).and_return(100)
      opening_executions << [invalid_execution]
      changes = [
        -> { executions_callback.last.call([{ 'price' => 1_010_000 }]) },
        lambda {
          allow(command).to receive(:monotonic_time).and_return(129)
          executions_callback.last.call([invalid_execution])
        },
        -> { allow(command).to receive(:monotonic_time).and_return(130) },
        -> { executions_callback.last.call([invalid_execution]) },
        -> { executions_callback.last.call([{ 'price' => '1020000' }]) }
      ]

      frames = capture_stdout { run_iterations(command, *changes) }.split("\e[4F\e[0J").drop(1)
      expect(frames.size).to eq(4)
      stale, marked, expired, renewed = frames
      expect(stale).to include('Current:  Stale', 'Spread:   N/A', 'Balance:  N/A (N/A)')
      expect(marked).to include('Current:  1,010,000', 'Balance:  51,000')
      expect(expired).to eq(stale)
      expect(renewed).to include('Current:  1,020,000', 'Balance:  52,000')
    end
  end

  shared_examples 'an invalidated execution price' do
    it 'withholds market-derived values after an account refresh until a new execution arrives' do
      command = described_class.new
      allow(command).to receive(:monotonic_time).and_return(100)
      opening_executions << [{ 'price' => 1_010_000 }]
      frames = capture_stdout do
        run_iterations(
          command,
          -> { invalidate_price.call(command) },
          lambda {
            refresh_account(command, price: 1_010_000, size: 0.2, collateral: 60_000)
            executions_callback.last.call([])
          },
          -> { executions_callback.last.call([{ 'price' => 1_020_000 }]) }
        )
      end.split("\e[4F\e[0J").drop(1)
      expect(frames.first).to include('Balance:  51,000')
      expect(frames[-2]).to include(
        'Current:  Stale', 'Position: 1,010,000 * 0.2', 'Spread:   N/A', 'Balance:  N/A (N/A)'
      )
      expect(frames.last).to include('Current:  1,020,000', 'Balance:  62,000')
      expect(frames.last).to match(/Spread:   \+.*10,000/).and match(/\(\+.*2,000.*\)/)
    end
  end

  context 'when the WebSocket disconnects' do
    let(:invalidate_price) { ->(_command) { disconnect_callback.last.call(nil) } }

    it_behaves_like 'an invalidated execution price'
  end

  context 'when the execution feed stalls silently' do
    let(:invalidate_price) do
      lambda do |command|
        allow(command).to receive(:monotonic_time).and_return(129.9)
        allow(command).to receive(:monotonic_time).and_return(130)
      end
    end

    it_behaves_like 'an invalidated execution price'
  end

  it 'builds one frame while the account and fresh price stay the same' do
    command = described_class.new
    allow(command).to receive(:monotonic_time).and_return(100)
    execution = [{ 'price' => 1_010_000 }]
    opening_executions << execution
    repeat_price = lambda do
      allow(command).to receive(:monotonic_time).and_return(129)
      executions_callback.last.call(execution)
    end
    expect(command).to receive(:frame).once.and_call_original

    output = capture_stdout { run_iterations(command, -> {}, repeat_price, -> {}) }

    expect(output.scan("\e[4F\e[0J").size).to eq(1)
  end

  it 'draws once when different prices produce the same visible values' do
    command = described_class.new
    opening_executions << [{ 'price' => 1_010_000 }]
    expect(command).to receive(:frame).twice.and_call_original

    output = capture_stdout do
      run_iterations(command, -> {}, -> { executions_callback.last.call([{ 'price' => 1_010_000.5 }]) }, -> {})
    end

    expect(output.scan("\e[4F\e[0J").size).to eq(1)
    expect(output).to include('Current:  1,010,000')
  end

  it 'redraws on the next iteration after a price, position, spread or balance change' do
    command = described_class.new
    changes = [
      -> { executions_callback.last.call([{ 'price' => 1_010_000 }]) },
      -> { refresh_account(command, price: 1_000_000, size: 0.2, collateral: 50_000) },
      -> { refresh_account(command, price: 1_005_000, size: 0.2, collateral: 50_000) },
      -> { refresh_account(command, price: 1_005_000, size: 0.2, collateral: 60_000) }
    ]

    output = capture_stdout { run_iterations(command, *changes) }
    frames = output.split("\e[4F\e[0J").drop(1)

    expect(frames.size).to eq(5)
    expect(frames[0]).to include('Current:  Stale', 'Balance:  N/A (N/A)')
    expect(frames[1]).to include('Current:  1,010,000')
    expect(frames[2]).to include('Position: 1,000,000 * 0.2')
    expect(frames[3]).to match(/Spread:   \+.*5,000/)
    expect(frames[4]).to include('Balance:  61,000')
  end

  it 'redraws when the price expires and when the same price becomes fresh again' do
    command = described_class.new
    allow(command).to receive(:monotonic_time).and_return(100)
    execution = [{ 'price' => 1_010_000 }]
    opening_executions << execution
    expire_price = -> { allow(command).to receive(:monotonic_time).and_return(130) }
    renew_price = -> { executions_callback.last.call(execution) }
    expect(command).to receive(:frame).exactly(3).times.and_call_original

    output = capture_stdout { run_iterations(command, expire_price, -> {}, renew_price) }
    frames = output.split("\e[4F\e[0J").drop(1)

    expect(frames.size).to eq(3)
    expect(frames[0]).to include('Current:  1,010,000', 'Balance:  51,000')
    expect(frames[1]).to include('Current:  Stale', 'Spread:   N/A', 'Balance:  N/A (N/A)')
    expect(frames[2]).to include('Current:  1,010,000', 'Balance:  51,000')
  end

  it 'renders new prices without rereading position rows' do
    command = described_class.new
    expect(positions).not_to receive(:each)
    expect(positions).not_to receive(:inject)
    expect(positions.first).not_to receive(:[])

    opening_executions << [{ 'price' => 1_010_000 }]
    first_frame = capture_stdout { run_once(command) }
    opening_executions << [{ 'price' => 1_020_000 }]
    second_frame = capture_stdout { run_once(command) }

    expect(first_frame).to include('Position: 1,000,000 * 0.1', 'Balance:  51,000')
    expect(second_frame).to include('Position: 1,000,000 * 0.1', 'Balance:  52,000')
  end

  it 'stops the poller and restores stdout on each interrupted run' do
    command = described_class.new
    started = Queue.new
    workers = []

    allow(command).to receive(:sleep).with(5) do
      started << Thread.current
      Thread.stop
    end
    allow(command).to receive(:sleep).with(0.1) do
      workers << Timeout.timeout(5) { started.pop }
      expect(workers.select(&:alive?)).to eq([workers.last])
      expect($stdout.sync).to be(true)
      raise Interrupt
    end

    [false, true].each do |original_sync|
      output = capture_stdout do
        $stdout.sync = original_sync
        command.run

        expect(workers.last).not_to be_alive
        expect($stdout.sync).to eq(original_sync)
      end
      expect(output).to start_with("\e[?25l").and end_with("\e[?25h")
    end
    expect(workers.uniq.size).to eq(2)
  ensure
    workers&.each { |worker| worker.kill.join }
  end

  context 'with a fractional short break-even price' do
    let(:positions) do
      [position(side: 'SELL', price: 10_000, size: 0.01), position(side: 'SELL', price: 10_001, size: 0.03)]
    end

    it 'displays the position price in whole yen' do
      output = capture_stdout { run_once(described_class.new) }

      expect(output).to include("Position: 10,000 * -0.04\n")
    end
  end

  context 'with offsetting positions' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.1), position(side: 'SELL', price: 1_100_000, size: 0.1)]
    end

    it 'shows zero net size and spread while retaining the profit' do
      command = described_class.new
      opening_executions << [{ 'price' => 1_010_000 }]

      output = capture_stdout { run_once(command) }

      expect(output).to include('Position: 0 * 0.0', "Spread:   +\e[0;32;49m0\e[0m", 'Balance:  60,000')
    end
  end

  context 'with a zero signed average and a nonzero net size' do
    let(:positions) do
      [position(side: 'BUY', price: 1_000_000, size: 0.2), position(side: 'SELL', price: 2_000_000, size: 0.1)]
    end

    it 'shows the spread from the signed average' do
      command = described_class.new
      opening_executions << [{ 'price' => 1_010_000 }]

      output = capture_stdout { run_once(command) }

      expect(output).to include('Position: 0 * 0.1')
      expect(output).to match(/Spread:   \+.*1,010,000/)
    end
  end

  def run_iterations(command, *changes)
    allow(Thread).to receive(:new)
    allow(command).to receive(:sleep).with(0.1) do
      raise Interrupt if changes.empty?

      changes.shift.call
    end
    command.run
  end

  def refresh_account(command, price:, size:, collateral:)
    stub_responses(
      private_client,
      positions: [position(side: 'BUY', price: price, size: size)],
      collateral: { 'collateral' => collateral }
    )
    command.send(:update_balance)
  end

  def capture_stdout
    original = $stdout
    reader, writer = IO.pipe
    $stdout = writer
    yield
    writer.close
    reader.read
  ensure
    $stdout = original
    writer.close unless writer.closed?
    reader.close
  end
end
