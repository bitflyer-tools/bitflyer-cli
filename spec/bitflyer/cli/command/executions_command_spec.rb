require 'spec_helper'

describe ExecutionsCommand do
  let(:client) { stub_persistent_client }

  it 'prints each fill on a separate row when looking up a child order' do
    fill = {
      'exec_date' => '2025-01-01T00:00:00.123', 'side' => 'SELL', 'price' => 30_000, 'size' => 0.01,
      'commission' => 0, 'child_order_id' => 'JOR-order', 'child_order_acceptance_id' => 'JRF-accepted'
    }
    stub_responses(client, executions: [fill, fill.merge(
      'exec_date' => '2025-01-01T00:00:01.456', 'price' => 30_100, 'size' => 0.02, 'commission' => 0.001
    )])

    expect { described_class.new.run(child_order_id: 'JOR-order') }.to output(<<~OUTPUT).to_stdout
      Execution time | Side | Price (JPY) | Size (BTC) | Commission | Child order ID | Acceptance ID
      2025-01-01T00:00:00.123 | SELL | 30000 | 0.01 | 0 | JOR-order | JRF-accepted
      2025-01-01T00:00:01.456 | SELL | 30100 | 0.02 | 0.001 | JOR-order | JRF-accepted
    OUTPUT
    expect(client).to have_received(:executions).with(product_code: 'FX_BTC_JPY', count: 100, child_order_id: 'JOR-order').once
  end

  it 'escapes terminal controls while preserving ordinary field text' do
    stub_responses(client, executions: [{
      'exec_date' => '2025-01-01T00:00:00', 'side' => 'SELL', 'price' => 30_000, 'size' => 0.01,
      'commission' => 0, 'child_order_id' => "JOR-\r注文\n", 'child_order_acceptance_id' => "JRF-\e[2J\u009B"
    }])

    expect { described_class.new.run }.to output(<<~'OUTPUT').to_stdout
      Execution time | Side | Price (JPY) | Size (BTC) | Commission | Child order ID | Acceptance ID
      2025-01-01T00:00:00 | SELL | 30000 | 0.01 | 0 | JOR-\r注文\n | JRF-\e[2J\u009B
    OUTPUT
  end

  it 'requests one bounded page of account executions by default' do
    stub_responses(client, executions: [])

    expect { described_class.new.run }.to output("No executions found.\n").to_stdout
    expect(client).to have_received(:executions).with(product_code: 'FX_BTC_JPY', count: 100).once
  end

  it 'rejects two filters before creating a private client' do
    expect(Bitflyer::Cli::PersistentHTTPClient).not_to receive(:new)

    expect { described_class.new.run(child_order_id: 'JOR-order', child_order_acceptance_id: 'JRF-accepted') }
      .to raise_error(described_class::LookupFailed, /Specify only one/)
  end

  it 'reports an unexpected response as a lookup failure' do
    stub_responses(client, executions: 'Service unavailable')

    expect { described_class.new.run }
      .to raise_error(described_class::LookupFailed, /Unexpected response from bitFlyer/)
  end

  it 'reports a network timeout as a lookup failure' do
    allow(client).to receive(:executions).and_raise(Net::ReadTimeout)

    expect { described_class.new.run }.to raise_error(described_class::LookupFailed, /Could not list executions/)
  end
end
