# frozen_string_literal: true

require 'colorize'

class String
  def color_with_number(number)
    sign = number >= 0.0 ? '+' : ''
    sign + colorize(number >= 0.0 ? :green : :red)
  end

  def split_by_comma
    reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
  end
end
