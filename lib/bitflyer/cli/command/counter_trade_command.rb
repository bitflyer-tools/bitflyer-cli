require 'bitflyer'

class CounterTradeCommand
  def initialize
    @http_client = Bitflyer.http_private_client(api_key, api_secret)
  end

  def run
    position = Position.new(@http_client.positions)
    size = position.size.abs
    type = position.size > 0 ? 'SELL' : 'BUY'
    response = @http_client.send_child_order(
        product_code: 'FX_BTC_JPY',
        child_order_type: 'MARKET',
        side: type,
        size: size
    )
    if response['child_order_acceptance_id'].nil?
      puts 'An error has occurred' + response.to_s
    else
      puts "Clear position #{type} / #{size}"
    end
  end

  private

  def api_key
    ENV['BITFLYER_API_KEY']
  end

  def api_secret
    ENV['BITFLYER_API_SECRET']
  end
end