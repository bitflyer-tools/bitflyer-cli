# frozen_string_literal: true

require 'bitflyer/cli/counter_trade_submission'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_rejected'
require 'bitflyer/cli/persistent_http_client'

class CounterTradeCommand
  include HasHTTPClient

  alias http_private_client persistent_http_client

  PRODUCT_CODE = 'FX_BTC_JPY'
  ACCEPTANCE_ID = 'child_order_acceptance_id'
  COMMUNICATION_ERRORS = [
    Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError,
    Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
  ].freeze
  TERMINAL_STATES = %w[COMPLETED CANCELED EXPIRED REJECTED].freeze

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
  rescue Net::HTTPBadResponse => e
    detail = e.api_error if e.is_a?(Bitflyer::Cli::PersistentHTTPClient::GetResponseError)
    raise PositionLookupFailed, "Failed to look up positions: #{detail || e.message}"
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
    executed = terminal_fill(id)
    unless before&.finite? && executed && executed <= before.abs
      submission.require_reconciliation("Previous counter trade (#{id}) is awaiting reconciliation.")
    end

    before.positive? ? before - executed : before + executed
  end

  def terminal_fill(id)
    order = terminal_order(id)
    return unless order

    size = BigDecimal(order['executed_size'].to_s, exception: false)
    size if size&.finite? && !size.negative?
  end

  def terminal_order(id)
    orders = persistent_http_client.child_order_by_acceptance_id(
      product_code: PRODUCT_CODE, child_order_acceptance_id: id
    )
    return unless orders.is_a?(Array) && orders.one?

    order = orders.first
    return unless order.is_a?(Hash) && order[ACCEPTANCE_ID] == id

    order if TERMINAL_STATES.include?(order['child_order_state'])
  rescue *COMMUNICATION_ERRORS
    nil
  end

  def place_order(submission, position)
    return puts "You don't have any position now." if position.empty?
    return puts 'Your net position is already flat.' if position.flat?

    size = position_order_size(position)
    return unless size

    side = position.size.positive? ? 'SELL' : 'BUY'
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
    status = response.status
    body = response.body
    id = body[ACCEPTANCE_ID] if body.is_a?(Hash)
    return submission.record(exposure, id) if Bitflyer::Cli::OrderRejected.accepted?(status, id, body)

    reject_order(submission, body) if id.nil? && definite_rejection?(status, body)
    submission.require_reconciliation("Could not verify counter trade acceptance (HTTP #{status}).")
  end

  def reject_order(submission, body)
    submission.clear
    Bitflyer::Cli::OrderRejected.check!(body, ACCEPTANCE_ID)
  end

  def send_market_order(client, submission, side, size)
    client.send_child_order(product_code: PRODUCT_CODE, child_order_type: 'MARKET', side: side, size: size)
  rescue *COMMUNICATION_ERRORS
    submission.require_reconciliation('Could not verify counter trade acceptance due to a communication error.')
  end

  def definite_rejection?(status, body)
    verifiable = status.between?(200, 299) || (status.between?(400, 499) && status != 408)
    verifiable && body.is_a?(Hash) && body['status'].is_a?(Integer) && body['status'].negative?
  end
end
