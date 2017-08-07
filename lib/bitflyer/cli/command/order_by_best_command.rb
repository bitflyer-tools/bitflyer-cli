require 'bitflyer/cli/has_http_client'

class OrderByBestCommand
  include HasHTTPClient

  def run(options)
    amount = options.amount
    type = options.type

    ticker = http_public_client.ticker('FX_BTC_JPY')
    price = type == 'buy' ? ticker['best_bid'] : ticker['best_ask']

    response = http_private_client.send_child_order(
        product_code: 'FX_BTC_JPY',
        child_order_type: 'LIMIT',
        side: type.upcase,
        price: price,
        size: amount
    )

    if response['child_order_acceptance_id'].nil?
      puts 'An error has occurred' + response.to_s
    else
      puts "An order is created #{type} / #{price} / #{amount}"
    end
  end
end