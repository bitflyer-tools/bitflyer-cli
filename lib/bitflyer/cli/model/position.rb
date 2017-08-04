class Position
  def initialize(positions)
    @positions = positions
  end

  def profit(current_price)
    @positions.inject(0.0) do |sum, position|
      sum + (current_price - position['price'].to_f) * position['size'].to_f * (position['side'] == 'BUY' ? 1.0 : -1.0)
    end
  end

  def average
    @positions.size > 0 ? (sum / size.abs).to_i : 0
  end

  def sum
    @positions.inject(0.0) do |sum, position|
      sum + position['price'].to_f * position['size'].to_f
    end
  end

  def size
    @positions.inject(0.0) { |sum, position| sum + position['size'].to_f * (position['side'] == 'BUY' ? 1.0 : -1.0) }.round(5)
  end
end
