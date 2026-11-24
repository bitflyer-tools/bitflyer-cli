# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/active_stop_lookup'
require 'bitflyer/cli/counter_trade_submission'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/parent_order_lookup'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/stop_submission'

class StopByRangeCommand
  include HasHTTPClient

  alias http_private_client persistent_http_client

  LookupFailed = Bitflyer::Cli::ParentOrderLookup::LookupFailed

  PRODUCT_CODE = 'FX_BTC_JPY'

  def run(options)
    raise ArgumentError, 'Range must be positive' unless options.range.positive?

    stop = current_stop(options.range)
    return unless stop

    coordinate_with_counter_trade(options.range, stop)
  ensure
    close_persistent_http_client
  end

  private

  def coordinate_with_counter_trade(range, stop)
    coordination = Bitflyer::Cli::CounterTradeSubmission.new(PRODUCT_CODE, api_key)
    submission = Bitflyer::Cli::StopSubmission.new(api_key, stop)
    coordination.synchronize do
      block_for_counter_trade!(coordination)
      submission.synchronize { place_stop(range, stop, submission) }
    end
  end

  def block_for_counter_trade!(coordination)
    pending = coordination.pending
    return unless pending

    raise Thor::Error, "A counter trade offset for #{PRODUCT_CODE} is unresolved. Resolve it before placing a " \
                       "stop; the position may not yet reflect the offset. Counter trade record: #{coordination.path}"
  end

  def current_stop_matches?(range, stop)
    refreshed_stop = current_stop(range)
    return false unless refreshed_stop
    raise LookupFailed, 'Position changed before stop placement. Run the command again.' if refreshed_stop != stop

    true
  end

  def place_stop(range, stop, submission)
    return unless current_stop_matches?(range, stop)

    pending = submission.pending
    description = stop.values_at(:side, :trigger_price, :size).join(' / ')
    order, conflicts = find_active_stop(stop, submission, pending)
    return puts "Existing stop order #{description} (#{order.fetch('parent_order_id')})" if order

    raise Thor::Error, "Conflicting active stop orders: #{conflicts.join(', ')}" unless conflicts.empty?

    return if pending && pending_stop?(submission, pending, description)
    return unless current_stop_matches?(range, stop)

    submit_stop(stop, description, submission)
  end

  def find_active_stop(stop, submission, pending)
    Bitflyer::Cli::ActiveStopLookup.new(http_private_client, parent_order_lookup).find(stop)
  rescue *Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS => e
    message = "Failed to look up active parent orders: #{e.message}."
    submission.raise_unverified(message) if pending == Bitflyer::Cli::StopSubmission::UNVERIFIED
    raise LookupFailed, message
  end

  def pending_stop?(submission, pending, description)
    id, state = submission.reconcile(pending, parent_order_lookup)
    return false if state && state != 'COMPLETED'

    if id == Bitflyer::Cli::StopSubmission::UNVERIFIED
      submission.raise_unverified("Stop order #{description} is unverified and awaiting confirmation.")
    end

    puts "Previous stop order #{description} (#{id}): #{state || 'awaiting confirmation'}"
    puts "Completed submission record: #{submission.path}" if state == 'COMPLETED'
    true
  end

  def current_stop(range)
    position = fetch_position
    return puts "You don't have any position now." if position.flat?

    size = position_order_size(position)
    return unless size

    side = position.size.positive? ? 'SELL' : 'BUY'
    trigger_price = stop_trigger_price(position.average, range, side)
    { product_code: PRODUCT_CODE, condition_type: 'STOP', side: side, trigger_price: trigger_price, size: size }
  end

  def stop_trigger_price(average, range, side)
    offset = range.to_s.to_d
    price = side == 'BUY' ? average + offset : average - offset
    if price.finite?
      # Round away from break-even to preserve the requested minimum distance.
      trigger = (side == 'BUY' ? price.ceil : price.floor).to_f
      return trigger if trigger.finite? && trigger.positive?
    end

    raise Thor::Error, 'Stop trigger price must be positive and finite.'
  end

  def parent_order_lookup
    Bitflyer::Cli::ParentOrderLookup.new(http_private_client, PRODUCT_CODE)
  end

  def submit_stop(stop, description, submission)
    submission.submit(Bitflyer::Cli::StopSubmission::ACCEPTANCE_ID) do
      http_private_client.send_parent_order(order_method: 'SIMPLE', parameters: [stop])
    end
    puts "Set stop order #{description}"
  end
end
