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
    allow(Thread).to receive(:new)
    allow(command).to receive(:sleep).and_raise(Interrupt)
    command.run
  end

  it 'loads the position and collateral on start' do
    described_class.new
    expect(private_client).to have_received(:positions)
    expect(private_client).to have_received(:collateral)
  end

  it 'prints the current price, spread and balance with profit' do
    command = described_class.new
    executions_callback.first.call([{ 'price' => 1_005_000 }, { 'price' => 1_010_000 }])

    output = capture_stdout { run_once(command) }

    expect(output).to include('Current:  1,010,000', 'Position: 1,000,000 * 0.1', 'Balance:  51,000')
    expect(output).to match(/Spread:   \+.*10,000/).and match(/\(\+.*1,000/)
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
