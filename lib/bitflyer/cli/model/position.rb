# frozen_string_literal: true

require 'bigdecimal'
require 'bigdecimal/util'

class Position
  attr_reader :size, :sum

  def initialize(positions)
    @empty = positions.empty?
    @size = @sum = @signed_entry_value = 0.to_d
    positions.each { |position| accumulate(position) }
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
    quantity = position['size'].to_s.to_d
    entry_value = position['price'].to_s.to_d * quantity
    sign = position['side'] == 'BUY' ? 1 : -1

    @size += quantity * sign
    @sum += entry_value
    @signed_entry_value += entry_value * sign
  end
end
