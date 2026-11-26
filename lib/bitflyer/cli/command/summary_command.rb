# frozen_string_literal: true

require 'colorize'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/realtime_client'
require 'bitflyer/cli/model/position'
require 'bitflyer/cli/persistent_http_client'

class SummaryCommand # rubocop:disable Metrics/ClassLength
  include HasHTTPClient

  alias http_private_client persistent_http_client

  PRICE_FRESHNESS_LIMIT = 30 # seconds

  def initialize
    update_balance
  rescue *Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS => e
    raise HasHTTPClient::AccountLookupFailed, "Failed to look up account: #{e.message}"
  ensure
    close_persistent_http_client unless @account_snapshot
  end

  def run # rubocop:disable Metrics/MethodLength
    stdout = $stdout
    original_sync = stdout.sync
    feed_worker = poller = nil

    Thread.handle_interrupt(Interrupt => :never) do
      stdout.sync = true
      stdout.print "\e[?25l"
      @execution = nil
      @feed = nil
      feed_worker = start_feed
      poller = Thread.new { poll_account }
    end

    render(feed_worker)
  rescue Interrupt
    # exit
  ensure
    Thread.handle_interrupt(Interrupt => :never) do
      restore_display(feed_worker, poller, stdout, original_sync)
    end
  end

  private

  def start_feed
    # The worker inherits the Interrupt mask and accepts cancellation during network I/O.
    Thread.start do
      Thread.current.report_on_exception = false
      @feed = Bitflyer::Cli::RealtimeClient.new
      Thread.handle_interrupt(Interrupt => :on_blocking) { subscribe_to_feed(@feed) }
    rescue Interrupt
      # Stopped by the display thread.
    end
  end

  def subscribe_to_feed(feed)
    feed.disconnected = ->(_error) { @execution = nil }
    feed.executions_fx_btc_jpy = lambda { |message|
      price = Float(message.last&.[]('price'), exception: false)
      @execution = [price, monotonic_time] if price&.finite? && price.positive?
    }
  end

  def stop_workers(feed_worker, poller)
    poller&.kill&.join
  ensure
    stop_feed(feed_worker)
  end

  def stop_feed(feed_worker)
    feed_worker&.raise(Interrupt)
    feed_worker&.join
  ensure
    @feed&.shutdown if feed_worker
  end

  def restore_display(feed_worker, poller, stdout, original_sync)
    stop_workers(feed_worker, poller)
  ensure
    close_http_and_restore_cursor(stdout, original_sync)
  end

  def close_http_and_restore_cursor(stdout, original_sync)
    close_persistent_http_client
  ensure
    stdout&.print "\e[?25h"
    stdout.sync = original_sync if stdout
  end

  def render(feed_worker)
    puts "\n" * 3
    previous_frame = previous_inputs = nil

    loop do
      feed_worker.value unless feed_worker.alive?
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
    balance = fetch_collateral
    @account_snapshot = [position, balance, false].freeze
  rescue HasHTTPClient::AccountLookupFailed => e
    raise unless @account_snapshot

    warn e.message
    mark_account_stale
  end

  def mark_account_stale
    @account_snapshot = [*@account_snapshot.first(2), true].freeze if @account_snapshot
  end

  def frame(account_snapshot, price)
    position, balance, stale = account_snapshot
    average = position.average.to_i
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

  def monotonic_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
