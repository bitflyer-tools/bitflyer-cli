require 'spec_helper'
require 'timeout'

describe SummaryCommand do
  let!(:private_client) { stub_private_client }
  let!(:realtime_client) { stub_realtime_client }
  let(:positions) { [position(side: 'BUY', price: 1_000_000, size: 0.1)] }
  let(:executions_callback) { [] }

  before do
    stub_responses(private_client, positions: positions, collateral: { 'collateral' => 50_000 })
    allow(realtime_client).to receive(:executions_fx_btc_jpy=) { |callback| executions_callback << callback }
  end

  def run_once(command)
    run_iterations(command)
  end

  context 'when the initial position lookup is rejected' do
    let(:positions) { { 'status' => -200, 'error_message' => 'Invalid API key' } }

    it 'reports the API error and skips account rendering' do
      expect(Position).not_to receive(:new)
      expect(Thread).not_to receive(:new)
      expect { described_class.new.run }.to output(/Failed to look up positions:.*-200.*Invalid API key/).to_stderr
      expect(private_client).not_to have_received(:collateral)
    end
  end

  context 'without any position' do
    let(:positions) { [] }

    it 'renders the empty position' do
      output = capture_stdout { run_once(described_class.new) }

      expect(output).to include('Position: 0 * 0.0')
    end
  end

  it 'reports a rejected refresh and keeps the last successful account data' do
    command = described_class.new
    stub_responses(private_client, positions: { 'status' => -200 })
    allow(Thread).to receive(:new).and_yield
    expect(command).to receive(:sleep).with(5).ordered
    expect(command).to receive(:sleep).with(5).ordered.and_raise(Interrupt)
    expect(Position).not_to receive(:new)

    expect { capture_stdout { command.run } }.to output(/Failed to look up positions:.*-200/).to_stderr
    expect(private_client).to have_received(:collateral).once
    expect(capture_stdout { run_once(command) }).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000')
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
    executions_callback.first.call([{ 'price' => 1_005_000 }, { 'price' => 1_010_000 }])

    output = capture_stdout { run_once(command) }

    expect(output).to include('Current:  1,010,000', 'Position: 1,000,000 * 0.1', 'Balance:  51,000')
    expect(output).to match(/Spread:   \+.*10,000/).and match(/\(\+.*1,000/)
  end

  it 'keeps the last complete account data until a scheduled refresh succeeds' do
    command = described_class.new
    new_positions = [position(side: 'BUY', price: 1_100_000, size: 0.2)]
    expect(private_client).to receive(:positions).ordered.and_return(new_positions)
    expect(private_client).to receive(:collateral).ordered.and_raise(IOError)
    expect(private_client).to receive(:positions).ordered.and_return(new_positions)
    expect(private_client).to receive(:collateral).ordered.and_return('collateral' => 60_000)

    poller = nil
    allow(Thread).to receive(:new) do |&poll|
      poller = Fiber.new(&poll)
      poller.resume
    end
    allow(command).to receive(:sleep).with(5) { Fiber.yield }
    expect(command).to receive(:sleep).with(0.1).exactly(3).times.and_invoke(
      ->(_) { poller.resume }, ->(_) { poller.resume }, ->(_) { raise Interrupt }
    )

    initial, stale, recovered = capture_stdout { command.run }.split("\e[4F\e[0J").drop(1)
    expect(initial).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000')
    expect(initial).not_to include('[stale]')
    expect(stale).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000', '[stale]')
    expect(recovered).to include('Position: 1,100,000 * 0.2', 'Balance:  60,000')
    expect(recovered).not_to include('[stale]')
  end

  it 'shows the previous account snapshot until collateral arrives' do
    command = described_class.new
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
    expect(output).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000')

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
    allow(private_client).to receive(:positions).and_return([position(side: 'BUY', price: 2_000_000, size: 0.2)])
    allow(private_client).to receive(:collateral).and_raise(IOError, 'Collateral request failed')

    expect { command.send(:update_balance) }.to raise_error(IOError, 'Collateral request failed')
    output = capture_stdout { run_once(command) }
    expect(output).to include('Position: 1,000,000 * 0.1', 'Balance:  50,000')
  end

  it 'uses the same price for the entire frame when an execution arrives during rendering' do
    account_position = Position.new(positions)
    allow(Position).to receive(:new).with(positions).and_return(account_position)
    command = described_class.new
    executions_callback.first.call([{ 'price' => 1_010_000 }])
    allow(account_position).to receive(:profit).and_wrap_original do |original, price|
      executions_callback.first.call([{ 'price' => 1_020_000 }])
      original.call(price)
    end

    output = capture_stdout { run_once(command) }

    expect(output).to include('Current:  1,010,000')
    expect(output).to match(/Spread:   \+.*10,000/).and match(/Balance:  51,000 +\(\+.*1,000/)
  end

  it 'shows no profit before any execution arrives' do
    output = capture_stdout { run_once(described_class.new) }

    expect(output).to include('Current:  0', 'Balance:  50,000')
  end

  it 'draws once when consecutive iterations have the same visible values' do
    command = described_class.new
    executions_callback.first.call([{ 'price' => 1_010_000 }])

    output = capture_stdout do
      run_iterations(command, -> {}, -> { executions_callback.first.call([{ 'price' => 1_010_000.5 }]) }, -> {})
    end

    expect(output.scan("\e[4F\e[0J").size).to eq(1)
    expect(output).to include('Current:  1,010,000')
  end

  it 'redraws on the next iteration after a price, position, spread or balance change' do
    command = described_class.new
    changes = [
      -> { executions_callback.first.call([{ 'price' => 1_010_000 }]) },
      -> { refresh_account(command, price: 1_000_000, size: 0.2, collateral: 50_000) },
      -> { refresh_account(command, price: 1_005_000, size: 0.2, collateral: 50_000) },
      -> { refresh_account(command, price: 1_005_000, size: 0.2, collateral: 60_000) }
    ]

    output = capture_stdout { run_iterations(command, *changes) }
    frames = output.split("\e[4F\e[0J").drop(1)

    expect(frames.size).to eq(5)
    expect(frames[0]).to include('Current:  0')
    expect(frames[1]).to include('Current:  1,010,000')
    expect(frames[2]).to include('Position: 1,000,000 * 0.2')
    expect(frames[3]).to match(/Spread:   \+.*5,000/)
    expect(frames[4]).to include('Balance:  61,000')
  end

  it 'renders new prices without rereading position rows' do
    command = described_class.new
    expect(positions).not_to receive(:each)
    expect(positions).not_to receive(:inject)
    expect(positions.first).not_to receive(:[])

    executions_callback.first.call([{ 'price' => 1_010_000 }])
    first_frame = capture_stdout { run_once(command) }
    executions_callback.first.call([{ 'price' => 1_020_000 }])
    second_frame = capture_stdout { run_once(command) }

    expect(first_frame).to include('Position: 1,000,000 * 0.1', 'Balance:  51,000')
    expect(second_frame).to include('Position: 1,000,000 * 0.1', 'Balance:  52,000')
  end

  it 'restores the cursor when interrupted' do
    output = capture_stdout { run_once(described_class.new) }

    expect(output).to start_with("\e[?25l").and end_with("\e[?25h")
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
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
