require 'spec_helper'

describe CancelAllCommand do
  it 'cancels all FX_BTC_JPY child orders' do
    stub_credentials
    result = CancellationClient::Result.new(:accepted, '200', nil, nil)
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    described_class.new.run

    expect(client).to have_received(:post).with('/v1/me/cancelallchildorders', product_code: 'FX_BTC_JPY')
  end

  it 'raises with the exchange message when the cancellation is rejected' do
    stub_credentials
    result = CancellationClient::Result.new(:rejected, '200', -205, 'Order not found.')
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run }.to raise_error(
      described_class::Rejected, 'Order not found.'
    )
  end

  it 'raises with the status when the rejection has no message' do
    stub_credentials
    result = CancellationClient::Result.new(:rejected, '200', -205, '')
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run }.to raise_error(
      described_class::Rejected, 'Cancel-all request rejected (status -205)'
    )
  end

  it 'raises an unverified failure when the HTTP status is unverified' do
    stub_credentials
    result = CancellationClient::Result.new(:unverified, '408', nil, nil)
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run }.to raise_error(
      described_class::Rejected, 'Could not verify cancel-all acceptance from bitFlyer (HTTP 408).'
    )
  end

  it 'includes the HTTP status for an unverified result with a non-408/5xx code' do
    stub_credentials
    result = CancellationClient::Result.new(:unverified, '404', nil, nil)
    client = instance_double(CancellationClient, post: result)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    expect { described_class.new.run }.to raise_error(
      described_class::Rejected, 'Could not verify cancel-all acceptance from bitFlyer (HTTP 404).'
    )
  end
end
