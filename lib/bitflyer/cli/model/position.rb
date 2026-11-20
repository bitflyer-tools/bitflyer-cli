# frozen_string_literal: true

require 'bigdecimal'
require 'bigdecimal/util'

class Position
  class InvalidRowError < StandardError; end

  DECIMAL = /\A[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z/

  attr_reader :size, :sum

  def initialize(positions)
    @empty = positions.empty?
    @size = @sum = @signed_entry_value = 0.to_d
    positions.each.with_index(1) do |position, row|
      accumulate(position)
    rescue InvalidRowError => e
      raise InvalidRowError, "row #{row}: #{e.message}"
    end
  end

  def profit(current_price)
    (current_price * size) - @signed_entry_value
  end

  def average
    flat? ? 0 : (@signed_entry_value / size).to_i
  end

  def flat?
    size.zero?
  end

  def empty?
    @empty
  end

  private

  def accumulate(position)
    sign = position_sign(position)
    quantity = positive_decimal(position, 'size')
    entry_value = positive_decimal(position, 'price') * quantity

    @size += quantity * sign
    @sum += entry_value
    @signed_entry_value += entry_value * sign
  end

  def position_sign(position)
    raise InvalidRowError, 'expected an object' unless position.is_a?(Hash)

    case position['side']
    when 'BUY' then 1
    when 'SELL' then -1
    else raise InvalidRowError, 'side must be BUY or SELL'
    end
  end

  def positive_decimal(position, field)
    raw = position[field].to_s
    value = BigDecimal(raw, exception: false) if DECIMAL.match?(raw)
    return value if value&.finite? && value.positive?

    raise InvalidRowError, "#{field} must be a positive, finite decimal"
  end
end
