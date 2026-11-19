require 'spec_helper'

describe OpenOrdersCommand do
  let(:client) { stub_private_client }

  it 'lists active child orders and parent strategies with their cancellation IDs' do
    stub_responses(client, child_orders: [{
      'child_order_id' => 'JOR-partial', 'child_order_type' => 'LIMIT', 'side' => 'BUY',
      'price' => 30_000, 'size' => 0.1, 'executed_size' => 0.06, 'outstanding_size' => 0.04
    }], parent_orders: [{
      'parent_order_id' => 'JCO-strategy', 'parent_order_type' => 'IFDOCO',
      'parent_order_date' => '2025-01-01T00:00:00'
    }])

    expect { described_class.new.run }.to output(<<~OUTPUT).to_stdout
      Child orders
      Order ID | Type | Side | Price (JPY) | Remaining size (BTC)
      JOR-partial | LIMIT | BUY | 30000 | 0.04
      Parent strategies
      Order ID | Strategy type | Order date
      JCO-strategy | IFDOCO | 2025-01-01T00:00:00
    OUTPUT
    expect(client).to have_received(:child_orders).with(product_code: 'FX_BTC_JPY', child_order_state: 'ACTIVE')
    expect(client).to have_received(:parent_orders).with(product_code: 'FX_BTC_JPY', parent_order_state: 'ACTIVE')
  end

  it 'shows an empty state for each order type' do
    stub_responses(client, child_orders: [], parent_orders: [])

    expect { described_class.new.run }.to output("Child orders\nNone.\nParent strategies\nNone.\n").to_stdout
  end

  it 'reports a lookup failure instead of showing an empty list' do
    stub_responses(client, child_orders: [], parent_orders: { 'status' => -1, 'error_message' => 'Permission denied' })

    expect { described_class.new.run }.to raise_error(described_class::LookupFailed, /parent orders.*Permission denied/)
  end
end
