require 'spec_helper'

describe CancelOrderCommand do
  before { stub_credentials }

  it 'cancels a child order' do
    result = CancellationClient::Result.new(:accepted, '200', nil, nil)
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run('child', 'JOR1') }.to output(
      "Cancellation request accepted for child order JOR1.\n"
    ).to_stdout

    expect(client).to have_received(:post).with('/v1/me/cancelchildorder', 'product_code' => 'FX_BTC_JPY',
                                                                              'child_order_id' => 'JOR1')
  end

  it 'cancels a parent strategy when confirmed' do
    result = CancellationClient::Result.new(:accepted, '200', nil, nil)
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run('parent', 'JOR2', confirm_parent: true) }.to output(
      "Cancellation request accepted for parent order JOR2.\n"
    ).to_stdout

    expect(client).to have_received(:post).with('/v1/me/cancelparentorder', 'product_code' => 'FX_BTC_JPY',
                                                                               'parent_order_id' => 'JOR2')
  end

  it 'rejects an invalid order type' do
    expect { described_class.new.run('child_order', 'JOR1') }.to raise_error(
      described_class::Failed, 'Order type must be child or parent.'
    )
  end

  it 'rejects a blank order id' do
    expect { described_class.new.run('child', '  ') }.to raise_error(
      described_class::Failed, 'Order ID is required.'
    )
  end

  it 'requires --confirm-parent to cancel a parent strategy' do
    expect { described_class.new.run('parent', 'JOR2') }.to raise_error(
      described_class::Failed,
      'Canceling a parent strategy also cancels its associated orders. Use --confirm-parent to proceed.'
    )
  end

  it 'raises with the exchange message when the cancellation is rejected' do
    result = CancellationClient::Result.new(:rejected, '200', -205, 'Order not found.')
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run('child', 'JOR1') }.to raise_error(
      described_class::Failed, 'Order not found.'
    )
  end

  it 'raises with the status when the rejection has no message' do
    result = CancellationClient::Result.new(:rejected, '200', -205, '')
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run('child', 'JOR1') }.to raise_error(
      described_class::Failed, 'Cancellation request rejected (status -205).'
    )
  end

  it 'raises an unverified failure when the HTTP status is unverified' do
    result = CancellationClient::Result.new(:unverified, '408', nil, nil)
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run('child', 'JOR1') }.to raise_error(
      described_class::Failed, 'Could not verify cancellation acceptance from bitFlyer (HTTP 408).'
    )
  end

  it 'includes the HTTP status for an unverified result with a non-408/5xx code' do
    result = CancellationClient::Result.new(:unverified, '404', nil, nil)
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run('child', 'JOR1') }.to raise_error(
      described_class::Failed, 'Could not verify cancellation acceptance from bitFlyer (HTTP 404).'
    )
  end
end
