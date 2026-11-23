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
    return print_preview(current_price, request.fetch(:parameters)) if options[:dry_run]

    submit_single_order('parent_order_acceptance_id') { |client| client.send_parent_order(**request) }
    print_confirmation(request.fetch(:parameters))
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
    validate_exit_prices!(side == 'BUY' ? [loss_price, profit_price] : [profit_price, loss_price], current_price)
    [profit_price, loss_price]
  rescue FloatDomainError
    raise Thor::Error, 'Exit prices must be finite.'
  end

  def validate_exit_prices!(prices, current_price)
    raise Thor::Error, 'Take-profit and stop prices must be positive after rounding.' unless prices.all?(&:positive?)

    lower, upper = prices
    return if lower < current_price && current_price < upper

    raise Thor::Error, 'Take-profit and stop prices must strictly bracket the reference price after rounding.'
  end

  def print_confirmation(parameters)
    market, limit, stop = parameters
    puts "Send market order #{market[:side]} / #{market[:size].to_f}"
    puts "Set limit order #{limit[:side]} / #{limit[:price]} / #{limit[:size].to_f}"
    puts "Set stop order #{stop[:side]} / #{stop[:trigger_price]} / #{stop[:size].to_f}"
  end

  def print_preview(current_price, parameters)
    market, limit, stop = parameters
    puts 'IFDOCO dry run (FX_BTC_JPY)'
    puts "Reference price: #{current_price} JPY"
    puts "Market entry: #{market[:side]} #{market[:size]} BTC"
    puts "Take-profit limit: #{limit[:side]} #{limit[:size]} BTC at #{limit[:price]} JPY"
    puts "Stop trigger: #{stop[:side]} #{stop[:size]} BTC at #{stop[:trigger_price]} JPY"
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
