# frozen_string_literal: true

require 'bigdecimal'
require 'bigdecimal/util'

class Position
  def initialize(positions)
    @positions = positions
  end

  def profit(current_price)
    @positions.inject('0'.to_d) do |sum, position|
      sum + ((current_price - position['price'].to_s.to_d) * position['size'].to_s.to_d * coefficient(position))
    end
  end

  def average
    @positions.size.positive? ? (sum / size.abs).to_i : 0
  end

  def sum
    @positions.inject('0'.to_d) { |sum, position| sum + (position['price'].to_s.to_d * position['size'].to_s.to_d) }
  end

  def size
    @positions.inject('0'.to_d) { |sum, position| sum + (position['size'].to_s.to_d * coefficient(position)) }
  end

  private

  def coefficient(position)
    position['side'] == 'BUY' ? 1.0 : -1.0
  end
end
