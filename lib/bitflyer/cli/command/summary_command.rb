# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/has_realtime_client'
require 'bitflyer/cli/ext/string'

class SummaryCommand
  include HasHTTPClient
  include HasRealtimeClient

  def initialize
    @current_price = 0.0

    realtime_client.executions_fx_btc_jpy = lambda { |message|
      message.each { |m| @current_price = m['price'].to_f }
    }

    update_balance
  end

  def run # rubocop:disable Metrics/MethodLength
    return unless @account_snapshot

    stdout = $stdout
    original_sync = stdout.sync
    stdout.sync = true
    print "\e[?25l"

    poller = nil
    Thread.handle_interrupt(Interrupt => :never) do
      poller = Thread.new { poll_balance }
    end

    display
  rescue Interrupt
    # exit
  ensure
    restore_display(poller, stdout, original_sync) if stdout
  end

  private

  def poll_balance
    loop do
      sleep 5
      update_balance
    end
  end

  def restore_display(poller, stdout, original_sync)
    poller&.kill
    poller&.join
  ensure
    stdout.print "\e[?25h"
    stdout.sync = original_sync
  end

  def display
    puts "\n" * 3
    previous_frame = nil

    loop do
      current_frame = frame
      if current_frame != previous_frame
        print current_frame
        previous_frame = current_frame
      end
      sleep 0.1
    end
  end

  def update_balance
    position = fetch_position
    return unless position

    balance = http_private_client.collateral['collateral'].to_i
    @account_snapshot = [position, balance].freeze
  end

  def frame # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    position, balance = @account_snapshot
    price = @current_price
    average = position.average
    profit = price.zero? ? 0 : position.profit(price).to_i
    spread = price.zero? || position.flat? ? 0 : price.to_i - average
    total = (balance + profit).to_s.split_by_comma.ljust(15)

    <<~EOS
      \e[4F\e[0JCurrent:  #{price.to_i.to_s.split_by_comma}
      Position: #{average.to_s.split_by_comma} * #{position.size.to_f}
      Spread:   #{spread.to_s.split_by_comma.color_with_number(spread)}
      Balance:  #{total} (#{profit.to_s.split_by_comma.color_with_number(profit)})
    EOS
  end
end
