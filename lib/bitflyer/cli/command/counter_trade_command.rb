require 'bitflyer/cli/has_http_client'

class CounterTradeCommand
  include HasHTTPClient

  def run
    position = Position.new(http_private_client.positions)
    size = position.size.abs.to_f
    type = position.size > 0 ? 'SELL' : 'BUY'
    response = http_private_client.send_child_order(
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
end