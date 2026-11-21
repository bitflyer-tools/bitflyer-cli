# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/order_rejected'
require 'bitflyer/cli/stop_submission'

class StopByRangeCommand
  include HasHTTPClient

  class LookupFailed < StandardError; end

  PRODUCT_CODE = 'FX_BTC_JPY'
  PAGE_SIZE = 100
  TERMINAL_STATES = %w[CANCELED EXPIRED REJECTED COMPLETED].freeze
  ACCEPTANCE_ID = 'parent_order_acceptance_id'

  def run(options)
    raise ArgumentError, 'Range must be positive' unless options.range.positive?

    position = fetch_position

    return puts "You don't have any position now." if position.flat?

    stop = stop_parameters(position, options.range)
    return unless stop

    submission = Bitflyer::Cli::StopSubmission.new(api_key, stop)
    submission.synchronize { place_stop(stop, submission) }
  end

  private

  def place_stop(stop, submission)
    pending = submission.pending
    description = stop.values_at(:side, :trigger_price, :size).join(' / ')
    if (order = find_parent_order('ACTIVE') { |entry| matching_stop?(entry, stop) })
      submission.clear if pending && order[ACCEPTANCE_ID] == pending
      return puts "Existing stop order #{description} (#{order.fetch('parent_order_id')})"
    end

    return if pending && pending_stop?(submission, pending, description)

    submit_stop(stop, description, submission)
  end

  def pending_stop?(submission, pending, description)
    state = terminal_state(pending)
    submission.clear if state
    return false if state && state != 'COMPLETED'

    puts "Previous stop order #{description} (#{pending}): #{state || 'awaiting confirmation'}"
    puts "Unverified submission record: #{submission.path}" if pending == Bitflyer::Cli::StopSubmission::UNVERIFIED
    true
  end

  def terminal_state(pending)
    return if pending == Bitflyer::Cli::StopSubmission::UNVERIFIED

    TERMINAL_STATES.find do |state|
      find_parent_order(state) { |order| order[ACCEPTANCE_ID] == pending }
    end
  end

  def stop_parameters(position, range)
    size = position_order_size(position)
    return unless size

    side = position.size.positive? ? 'SELL' : 'BUY'
    {
      product_code: PRODUCT_CODE,
      condition_type: 'STOP',
      side: side,
      trigger_price: position.average + (range * (side == 'BUY' ? 1.0 : -1.0)),
      size: size
    }
  end

  def find_parent_order(state, &match_order)
    before = nil
    loop do
      orders = parent_orders(state, before)
      match = orders.find(&match_order)
      return match if match
      return if orders.size < PAGE_SIZE

      before = next_cursor(orders, before)
    end
  end

  def next_cursor(orders, before)
    ids = orders.map { |order| order['id'] }
    if ids.all? { |id| id.is_a?(Integer) && id.positive? }
      cursor = ids.min
      return cursor if before.nil? || cursor < before
    end

    raise LookupFailed, 'Could not paginate active parent orders.'
  end

  def parent_orders(state, before)
    orders = http_private_client.parent_orders(
      product_code: PRODUCT_CODE, parent_order_state: state, count: PAGE_SIZE, before: before
    )
    return orders if orders.is_a?(Array)

    raise LookupFailed, "Failed to look up #{state.downcase} parent orders: #{orders.inspect}"
  end

  def matching_stop?(order, stop)
    return false unless order['parent_order_type'] == 'STOP'

    detail = parent_order_detail(order.fetch('parent_order_id'))
    parameters = detail.fetch('parameters')
    detail['order_method'] == 'SIMPLE' && parameters.one? &&
      stop.all? { |key, value| parameters.first[key.to_s] == value }
  end

  def parent_order_detail(order_id)
    detail = http_private_client.parent_order(parent_order_id: order_id)
    return detail if detail.is_a?(Hash) && detail['parameters'].is_a?(Array)

    raise LookupFailed, "Failed to look up parent order #{order_id}: #{detail.inspect}"
  end

  def submit_stop(stop, description, submission)
    submission.record(Bitflyer::Cli::StopSubmission::UNVERIFIED)
    response = http_private_client.send_parent_order(order_method: 'SIMPLE', parameters: [stop])
    if response.is_a?(Hash) && response[ACCEPTANCE_ID].nil? && response['status'].is_a?(Integer) &&
       response['status'].negative?
      submission.clear
    end
    Bitflyer::Cli::OrderRejected.check!(response, ACCEPTANCE_ID)
    submission.record(response.fetch(ACCEPTANCE_ID).to_s)
    puts "Set stop order #{description}"
  end
end
