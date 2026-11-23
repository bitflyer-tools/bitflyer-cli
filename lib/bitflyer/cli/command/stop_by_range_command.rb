# frozen_string_literal: true

require 'thor'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/stop_submission'

class StopByRangeCommand # rubocop:disable Metrics/ClassLength
  include HasHTTPClient

  alias http_private_client persistent_http_client

  class LookupFailed < StandardError; end

  PRODUCT_CODE = 'FX_BTC_JPY'
  PAGE_SIZE = 100
  HISTORY_REQUEST_LIMIT = 10
  TERMINAL_STATES = %w[CANCELED EXPIRED REJECTED COMPLETED].freeze
  ACCEPTANCE_ID = 'parent_order_acceptance_id'

  def run(options)
    raise ArgumentError, 'Range must be positive' unless options.range.positive?

    stop = current_stop(options.range)
    return unless stop

    submission = Bitflyer::Cli::StopSubmission.new(api_key, stop)
    submission.synchronize { place_stop(options.range, stop, submission) }
  ensure
    close_persistent_http_client
  end

  private

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
    if (order = find_active_stop(stop, submission, pending))
      return puts "Existing stop order #{description} (#{order.fetch('parent_order_id')})"
    end

    return if pending && pending_stop?(submission, pending, description)
    return unless current_stop_matches?(range, stop)

    submit_stop(stop, description, submission)
  end

  def find_active_stop(stop, submission, pending)
    find_parent_order('ACTIVE') { |entry| matching_stop?(entry, stop) }
  rescue Timeout::Error, SocketError, SystemCallError, IOError,
         OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError => e
    message = "Failed to look up active parent orders: #{e.message}."
    submission.raise_unverified(message) if pending == Bitflyer::Cli::StopSubmission::UNVERIFIED
    raise LookupFailed, message
  end

  def pending_stop?(submission, pending, description)
    id, state = submission.reconcile(pending) { terminal_state(pending, submission.path) }
    return false if state && state != 'COMPLETED'

    if id == Bitflyer::Cli::StopSubmission::UNVERIFIED
      submission.raise_unverified("Stop order #{description} is unverified and awaiting confirmation.")
    end

    puts "Previous stop order #{description} (#{id}): #{state || 'awaiting confirmation'}"
    puts "Completed submission record: #{submission.path}" if state == 'COMPLETED'
    true
  end

  def terminal_state(pending, record_path)
    request_page = history_page_reader(pending, record_path)
    TERMINAL_STATES.find do |state|
      find_parent_order(state, request_page: request_page) { |order| order[ACCEPTANCE_ID] == pending }
    end
  end

  def history_page_reader(pending, record_path)
    remaining_requests = HISTORY_REQUEST_LIMIT
    lambda do |state, before|
      if remaining_requests.zero?
        raise Thor::Error, "Stop order #{pending} still requires reconciliation after " \
                           "#{HISTORY_REQUEST_LIMIT} history requests. Submission record: #{record_path}"
      end

      remaining_requests -= 1
      parent_orders(state, before)
    end
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

  def find_parent_order(state, request_page: method(:parent_orders), &match_order)
    before = nil
    loop do
      orders = request_page.call(state, before)
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
    return false unless stop_candidate?(order, stop)

    detail = parent_order_detail(order.fetch('parent_order_id'))
    parameters = detail.fetch('parameters')
    detail['order_method'] == 'SIMPLE' && parameters.one? &&
      stop.all? { |key, value| parameters.first[key.to_s] == value }
  end

  def stop_candidate?(order, stop)
    order['parent_order_type'] == 'STOP' &&
      !opposite_side?(order['side'], stop.fetch(:side)) &&
      !different_size?(order['size'], stop.fetch(:size))
  end

  def opposite_side?(side, expected_side)
    %w[BUY SELL].include?(side) && side != expected_side
  end

  def different_size?(size, expected_size)
    (size.is_a?(Integer) || size.is_a?(Float)) && size.finite? && size.positive? && size != expected_size
  end

  def parent_order_detail(order_id)
    detail = http_private_client.parent_order(parent_order_id: order_id)
    return detail if detail.is_a?(Hash) && detail['parameters'].is_a?(Array)

    raise LookupFailed, "Failed to look up parent order #{order_id}: #{detail.inspect}"
  end

  def submit_stop(stop, description, submission)
    submission.submit(ACCEPTANCE_ID) do
      http_private_client.send_parent_order(order_method: 'SIMPLE', parameters: [stop])
    end
    puts "Set stop order #{description}"
  end
end
