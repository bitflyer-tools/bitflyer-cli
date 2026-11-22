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
end
