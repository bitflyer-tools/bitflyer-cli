# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_amount'

class IFDOCOByRangeCommand
  include HasHTTPClient

  def run(options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    side = options.type.upcase
    size = OrderAmount.validate!(options.amount)
    ratio = options.percentage.to_f
    range = options.range.to_f
    validate_inputs!(side: side, range: range, ratio: ratio)

    current_price = fetch_ticker_price('ltp')
    profit_price, loss_price = exit_prices(side: side, current_price: current_price, range: range, ratio: ratio)
    request = request(side: side, size: size, profit_price: profit_price, loss_price: loss_price)
    response = http_private_client.send_parent_order(**request)

    if response['parent_order_acceptance_id'].nil?
      puts "An error has occurred#{response}"
    else
      print_confirmation(request.fetch(:parameters))
    end
  end

  private

  def validate_inputs!(side:, range:, ratio:)
    raise Thor::Error, 'Order type must be buy or sell.' unless %w[BUY SELL].include?(side)
    raise Thor::Error, 'Range must be positive and finite.' unless range.positive? && range.finite?
    return if ratio.positive? && ratio < 100

    raise Thor::Error, 'Percentage must be greater than 0 and less than 100.'
  end

  def exit_prices(side:, current_price:, range:, ratio:)
    direction = side == 'BUY' ? 1 : -1
    profit_price = (current_price + (direction * range * ratio / 100.0)).to_i
    loss_price = (current_price - (direction * range * (100.0 - ratio) / 100.0)).to_i
    lower, upper = side == 'BUY' ? [loss_price, profit_price] : [profit_price, loss_price]
    unless lower < current_price && current_price < upper
      raise Thor::Error, 'Take-profit and stop prices must strictly bracket the reference price after rounding.'
    end

    [profit_price, loss_price]
  rescue FloatDomainError
    raise Thor::Error, 'Exit prices must be finite.'
  end

  def print_confirmation(parameters)
    market, limit, stop = parameters
    puts "Send market order #{market[:side]} / #{market[:size].to_f}"
    puts "Set limit order #{limit[:side]} / #{limit[:price]} / #{limit[:size].to_f}"
    puts "Set stop order #{stop[:side]} / #{stop[:trigger_price]} / #{stop[:size].to_f}"
  end

  def request(side:, size:, profit_price:, loss_price:) # rubocop:disable Metrics/MethodLength
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
end
