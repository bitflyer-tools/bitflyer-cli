# frozen_string_literal: true

require 'colorize'

class SummaryFrame
  class << self
    def render(account_snapshot, price)
      position, balance, stale = account_snapshot
      average = position.average
      values = price ? marked_values(price, position, balance, average) : "Spread:   N/A\nBalance:  N/A (N/A)"
      <<~EOS
        \e[4F\e[0JCurrent:  #{price ? group_digits(price.to_i) : 'Stale'}
        Position: #{group_digits(average)} * #{position.size.to_f}
        #{values}#{' [stale]' if stale}
      EOS
    end

    private

    def marked_values(price, position, balance, average)
      profit = position.profit(price).to_i
      spread = position.flat? ? 0 : price.to_i - average
      <<~EOS.chomp
        Spread:   #{colored_amount(spread)}
        Balance:  #{group_digits(balance + profit).ljust(15, ' ')} (#{colored_amount(profit)})
      EOS
    end

    def colored_amount(amount)
      formatted = group_digits(amount)
      amount >= 0 ? "+#{formatted.colorize(:green)}" : formatted.colorize(:red)
    end

    def group_digits(amount)
      amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
    end
  end
end
