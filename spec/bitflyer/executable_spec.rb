require 'spec_helper'

describe 'bitflyer executable' do
  let(:private_client) { stub_private_client }

  def run_cli(*args)
    stub_const('ARGV', args)
    load File.expand_path('../../exe/bitflyer', __dir__)
  end

  it 'prints a cancel-all rejection to stderr and exits unsuccessfully' do
    stub_responses(private_client, cancel_all_child_orders: { 'status' => -200, 'error_message' => 'rejected' })

    expect do
      expect { run_cli('cancel_all') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("rejected\n").to_stderr
  end

  it 'completes normally when the cancellation is accepted' do
    stub_responses(private_client, cancel_all_child_orders: '')

    expect { run_cli('cancel_all') }.to output('').to_stderr
  end

  it 'routes open_orders through the CLI' do
    stub_responses(private_client, child_orders: [], parent_orders: [])

    expect { run_cli('open_orders') }.to output("Child orders\nNone.\nParent strategies\nNone.\n").to_stdout
  end

  it 'requests cancellation of only the specified child order' do
    stub_responses(private_client, cancel_child_order: '', cancel_parent_order: '', cancel_all_child_orders: '')

    expect { run_cli('cancel_order', 'child', 'JOR-order') }
      .to output("Cancellation request accepted for child order JOR-order.\n").to_stdout
    expect(private_client).to have_received(:cancel_child_order).once
      .with(product_code: 'FX_BTC_JPY', child_order_id: 'JOR-order')
    expect(private_client).not_to have_received(:cancel_parent_order)
    expect(private_client).not_to have_received(:cancel_all_child_orders)
  end

  it 'requests parent cancellation when explicitly confirmed' do
    stub_responses(private_client, cancel_parent_order: '')

    expect { run_cli('cancel_order', 'parent', 'JCO-order', '--confirm-parent') }
      .to output("Cancellation request accepted for parent order JCO-order.\n").to_stdout
    expect(private_client).to have_received(:cancel_parent_order).once
      .with(product_code: 'FX_BTC_JPY', parent_order_id: 'JCO-order')
  end

  it 'requires confirmation before contacting bitFlyer to cancel a parent strategy' do
    stub_responses(private_client, cancel_parent_order: '')

    expect do
      expect { run_cli('cancel_order', 'parent', 'JCO-order') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/associated orders.*--confirm-parent/).to_stderr
    expect(private_client).not_to have_received(:cancel_parent_order)
  end

  it 'rejects an unknown order type before contacting bitFlyer' do
    stub_responses(private_client, cancel_child_order: '', cancel_parent_order: '')

    expect do
      expect { run_cli('cancel_order', 'other', 'JOR-order') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/Order type must be child or parent/).to_stderr
    expect(private_client).not_to have_received(:cancel_child_order)
    expect(private_client).not_to have_received(:cancel_parent_order)
  end

  it 'requires an order ID before contacting bitFlyer' do
    stub_responses(private_client, cancel_child_order: '')

    expect do
      expect { run_cli('cancel_order', 'child') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Order ID is required.\n").to_stderr
    expect(private_client).not_to have_received(:cancel_child_order)
  end

  it 'reports a rejected cancellation on stderr and exits unsuccessfully' do
    stub_responses(private_client, cancel_child_order: { 'status' => -200, 'error_message' => 'Order is no longer active.' })

    expect do
      expect { run_cli('cancel_order', 'child', 'JOR-order') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Cancellation request rejected. Order is no longer active.\n").to_stderr
  end

  it 'reports when an unexpected response leaves acceptance unverified' do
    stub_responses(private_client, cancel_child_order: 'Bad Gateway')

    expect do
      expect { run_cli('cancel_order', 'child', 'JOR-order') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("Could not verify cancellation acceptance from bitFlyer.\n").to_stderr
  end
end
