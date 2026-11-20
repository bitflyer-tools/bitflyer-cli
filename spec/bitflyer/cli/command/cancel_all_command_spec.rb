require 'spec_helper'

describe CancelAllCommand do
  it 'cancels all FX_BTC_JPY child orders' do
    stub_credentials
    response = instance_double(Net::HTTPResponse, code: '200', body: nil)
    client = instance_double(CancellationClient, post: response)
    allow(CancellationClient).to receive(:new).with('key', 'secret').and_return(client)

    described_class.new.run

    expect(client).to have_received(:post).with('/v1/me/cancelallchildorders', product_code: 'FX_BTC_JPY')
  end
end
