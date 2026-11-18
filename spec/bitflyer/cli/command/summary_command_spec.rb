require 'spec_helper'

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
    allow(Thread).to receive(:new)
    allow(command).to receive(:sleep).and_raise(Interrupt)
    command.run
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

  it 'shows no profit before any execution arrives' do
    output = capture_stdout { run_once(described_class.new) }

    expect(output).to include('Current:  0', 'Balance:  50,000')
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

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
