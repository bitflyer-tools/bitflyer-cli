require 'thor'

# Builds real bitflyer gem clients on top of a stubbed connection, so calls are checked
# against the gem's real method signatures without sending any HTTP request.
module ClientDoubles
  def stub_public_client
    with_stubbed_connection { Bitflyer::HTTP::Public::Client.new }.tap do |client|
      allow(Bitflyer).to receive(:http_public_client).and_return(client)
    end
  end

  def stub_private_client
    stub_credentials
    with_stubbed_connection { Bitflyer::HTTP::Private::Client.new('key', 'secret') }.tap do |client|
      allow(Bitflyer).to receive(:http_private_client).and_return(client)
    end
  end

  def stub_realtime_client
    instance_double(Bitflyer::Realtime::Client, :executions_fx_btc_jpy= => nil).tap do |client|
      allow(Bitflyer).to receive(:realtime_client).and_return(client)
    end
  end

  def stub_responses(client, responses)
    responses.each do |method_name, body|
      allow(client).to receive(method_name).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs)
        body
      end
    end
  end

  def thor_options(hash)
    Thor::CoreExt::HashWithIndifferentAccess.new(hash)
  end

  def position(side:, price:, size:)
    { 'side' => side, 'price' => price, 'size' => size }
  end

  private

  def stub_credentials
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('BITFLYER_API_KEY').and_return('key')
    allow(ENV).to receive(:[]).with('BITFLYER_API_SECRET').and_return('secret')
  end

  def with_stubbed_connection
    empty_response = Bitflyer::HTTP::Response.new({})
    connection = instance_double(Bitflyer::HTTP::Connection, get: empty_response, post: empty_response)
    allow(Bitflyer::HTTP::Connection).to receive(:new).and_return(connection)
    yield
  end
end
