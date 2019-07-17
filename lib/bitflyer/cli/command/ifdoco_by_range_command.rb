require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/model/position'

class IFDOCOByRangeCommand
  include HasHTTPClient

  def run(options)
    side = options.type.upcase
    size = options.amount.abs
    ratio = options.percentage.to_f
    range = options.range.to_f

    current_price = http_public_client.ticker(product_code: 'FX_BTC_JPY')['ltp'].to_i
    profit_price = profit_line(side: side, current_price: current_price, range: range, ratio: ratio).to_i
    loss_price = loss_line(side: side, current_price: current_price, range: range, ratio: ratio).to_i
    request = request(side: side, size: size, profit_price: profit_price, loss_price: loss_price)
    response = http_private_client.send_parent_order(request)

    if response['parent_order_acceptance_id'].nil?
      puts 'An error has occurred' + response.to_s
    else
      puts "Send market order #{side} / #{size.to_f}"
      puts "Set limit order #{side} / #{profit_price} / #{size.to_f}"
      puts "Set stop order #{side} / #{loss_price} / #{size.to_f}"
    end
  end

  private

  def request(side:, size:, profit_price:, loss_price:)
    {
      order_method: 'IFDOCO',
      time_in_force: 'GTC',
      parameters: [
        {
          product_code: 'FX_BTC_JPY',
          condition_type: 'MARKET',
          side: side,
          size: size
        },
        {
          product_code: 'FX_BTC_JPY',
          condition_type: 'LIMIT',
          side: side == 'BUY' ? 'SELL' : 'BUY',
          price: profit_price,
          size: size
        },
        {
          product_code: 'FX_BTC_JPY',
          condition_type: 'STOP',
          side: side == 'BUY' ? 'SELL' : 'BUY',
          trigger_price: loss_price,
          size: size
        }
      ]
    }
  end

  def profit_line(side:, current_price:, range:, ratio:)
    if side == 'BUY'
      current_price + range * ratio / 100.0
    elsif side == 'SELL'
      current_price - range * ratio / 100.0
    else
      0
    end
  end

  def loss_line(side:, current_price:, range:, ratio:)
    if side == 'BUY'
      current_price - range * (100.0 - ratio) / 100.0
    elsif side == 'SELL'
      current_price + range * (100.0 - ratio) / 100.0
    else
      0
    end
  end
end