require 'spec_helper'

describe CancelAllCommand do
  let!(:private_client) { stub_private_client }

  it 'cancels all FX_BTC_JPY child orders' do
    stub_responses(private_client, cancel_all_child_orders: {})
    described_class.new.run
    expect(private_client).to have_received(:cancel_all_child_orders).with(product_code: 'FX_BTC_JPY')
  end
end
