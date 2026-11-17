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
    run_iterations(command)
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
