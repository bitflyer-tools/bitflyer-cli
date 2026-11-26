# frozen_string_literal: true

require 'bitflyer/cli/counter_trade_submission'
require 'bitflyer/cli/counter_trade_terminal_order_lookup'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_rejected'
require 'bitflyer/cli/protective_stop_check'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/terminal_text'

class CounterTradeCommand
  include HasHTTPClient

  alias http_private_client persistent_http_client

  PRODUCT_CODE = 'FX_BTC_JPY'
  ACCEPTANCE_ID = 'child_order_acceptance_id'
  COMMUNICATION_ERRORS = Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS

  def run
    submission = Bitflyer::Cli::CounterTradeSubmission.new(PRODUCT_CODE, api_key)
    submission.synchronize { trade(submission, submission.pending) }
  ensure
    close_persistent_http_client
  end

  private

  def trade(submission, pending)
    position = pending ? reconcile_position(submission, pending) : fetch_position
    place_order(submission, position)
  end

  def reconcile_position(submission, pending)
    expected = expected_exposure(submission, pending)
    position = fetch_position
    unless position.size == expected
      submission.require_reconciliation('The previous counter trade is terminal, but its exposure is not confirmed.')
    end

    submission.clear
    position
  rescue PositionLookupFailed, *COMMUNICATION_ERRORS => e
    submission.require_reconciliation("Could not confirm exposure after the previous counter trade: #{e.message}")
  end

  def expected_exposure(submission, pending)
    id = pending['acceptance_id']
    unless Bitflyer::Cli::OrderRejected.acceptance_id?(id)
      submission.require_reconciliation('Previous counter trade acceptance is unverified.')
    end

    before = BigDecimal(pending['exposure'].to_s, exception: false)
    executed = terminal_order_lookup.executed_size(submission, id)
    unless before&.finite? && executed && executed <= before.abs
      escaped_id = Bitflyer::Cli::TerminalText.escape(id)
      submission.require_reconciliation("Previous counter trade (#{escaped_id}) is awaiting reconciliation.")
    end

    before.positive? ? before - executed : before + executed
  end

  def terminal_order_lookup
    @terminal_order_lookup ||= Bitflyer::Cli::CounterTradeTerminalOrderLookup.new(persistent_http_client, PRODUCT_CODE)
  end

  def place_order(submission, position)
    return puts "You don't have any position now." if position.empty?
    return puts 'Your net position is already flat.' if position.flat?

    size = position_order_size(position)
    return unless size

    side = position.size.positive? ? 'SELL' : 'BUY'
    Bitflyer::Cli::ProtectiveStopCheck.new(persistent_http_client, PRODUCT_CODE).verify!(side)
    submit_order(submission, position.size, side, size)
    puts "Clear position #{side} / #{size}"
  end

  def submit_order(submission, exposure, side, size)
    client = persistent_http_client
    submission.record(exposure)
    response = send_market_order(client, submission, side, size)
    record_response(submission, exposure, response)
  end

  def record_response(submission, exposure, response)
    case Bitflyer::Cli::OrderRejected.classify(response, ACCEPTANCE_ID)
    when :accepted
      submission.record(exposure, response.body.fetch(ACCEPTANCE_ID))
    when :rejected
      submission.clear
      Bitflyer::Cli::OrderRejected.raise_rejection!(response.body)
    else
      submission.require_reconciliation("Could not verify counter trade acceptance (HTTP #{response.status}).")
    end
  end

  def send_market_order(client, submission, side, size)
    client.send_child_order(product_code: PRODUCT_CODE, child_order_type: 'MARKET', side: side, size: size)
  rescue *COMMUNICATION_ERRORS
    submission.require_reconciliation('Could not verify counter trade acceptance due to a communication error.')
  end
end
