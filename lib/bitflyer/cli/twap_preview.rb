# frozen_string_literal: true

require 'bigdecimal'

module Bitflyer
  module Cli
    module TWAPPreview
      def self.print(side, amount, number, interval)
        total = BigDecimal(amount.to_s) * number
        duration = BigDecimal(interval.to_s) * (number - 1)
        puts 'TWAP dry run (FX_BTC_JPY)'
        puts "Side: #{side}"
        puts "Size per slice: #{amount} BTC"
        puts "Slice count: #{number}"
        puts "Total size: #{total.to_s('F')} BTC"
        puts "Interval: #{interval} seconds"
        puts "Planned time from first to last slice: #{duration.to_s('F')} seconds"
      end
    end
  end
end
