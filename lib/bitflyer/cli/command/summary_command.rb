# frozen_string_literal: true

require 'colorize'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/has_realtime_client'
require 'bitflyer/cli/model/position'
require 'bitflyer/cli/persistent_http_client'

class SummaryCommand
  include HasHTTPClient
  include HasRealtimeClient

  alias http_private_client persistent_http_client

  PRICE_FRESHNESS_LIMIT = 30 # seconds

  def initialize
    @execution = nil
    realtime_client.disconnected = ->(_error) { @execution = nil }
    realtime_client.executions_fx_btc_jpy = lambda { |message|
      price = Float(message.last&.[]('price'), exception: false)
      @execution = [price, monotonic_time] if price&.finite? && price.positive?
    }

    update_balance
  ensure
    close_persistent_http_client unless @account_snapshot
  end

  def run # rubocop:disable Metrics/MethodLength
    return unless @account_snapshot

    stdout = $stdout
    original_sync = stdout.sync
    stdout.sync = true
    print "\e[?25l"

    poller = nil
    Thread.handle_interrupt(Interrupt => :never) { poller = Thread.new { poll_account } }

    render
  rescue Interrupt
    # exit
  ensure
    restore_display(poller, stdout, original_sync)
  end

  private

  def restore_display(poller, stdout, original_sync)
    poller&.kill&.join
  ensure
    close_persistent_http_client
    stdout&.print "\e[?25h"
    stdout.sync = original_sync if stdout
  end

  def render
    puts "\n" * 3
    previous_frame = previous_inputs = nil

    loop do
      previous_inputs, previous_frame = redraw(previous_inputs, previous_frame)
      sleep 0.1
    end
  end

  def redraw(previous_inputs, previous_frame)
    inputs = [@account_snapshot, fresh_price]
    return previous_inputs, previous_frame if inputs == previous_inputs

    current_frame = frame(*inputs)
    print current_frame unless current_frame == previous_frame
    [inputs, current_frame]
  end

  def poll_account
    loop do
      sleep 5
      update_balance
    rescue IOError, Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      mark_account_stale
    end
  end

  def update_balance
    position = fetch_position
    return mark_account_stale unless position

    balance = http_private_client.collateral['collateral'].to_i
    @account_snapshot = [position, balance, false].freeze
  end

  def mark_account_stale
    return unless @account_snapshot

    @account_snapshot = [*@account_snapshot.first(2), true].freeze
  end

  def frame(account_snapshot, price)
    position, balance, stale = account_snapshot
    average = position.average
    values = price ? marked_values(price, position, balance, average) : "Spread:   N/A\nBalance:  N/A (N/A)"
    <<~EOS
      \e[4F\e[0JCurrent:  #{price ? group_digits(price.to_i) : 'Stale'}
      Position: #{group_digits(average)} * #{position.size.to_f}
      #{values}#{' [stale]' if stale}
    EOS
  end

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

  def fresh_price
    price, received_at = @execution
    price if received_at && monotonic_time - received_at < PRICE_FRESHNESS_LIMIT
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
