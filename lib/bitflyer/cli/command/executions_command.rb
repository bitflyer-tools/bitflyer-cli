# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/terminal_text'

class ExecutionsCommand
  include HasHTTPClient

  class LookupFailed < StandardError; end

  PAGE_SIZE = 100
  HEADER = 'Execution time | Side | Price (JPY) | Size (BTC) | Commission | Child order ID | Acceptance ID'
  FIELDS = %w[exec_date side price size commission child_order_id child_order_acceptance_id].freeze

  def run(child_order_id: nil, child_order_acceptance_id: nil)
    if child_order_id && child_order_acceptance_id
      raise LookupFailed, 'Specify only one of --child-order-id and --child-order-acceptance-id.'
    end

    filters = { child_order_id: child_order_id, child_order_acceptance_id: child_order_acceptance_id }.compact
    executions = fetch_executions(filters)
    return puts 'No executions found.' if executions.empty?

    rows = executions.map { |execution| Bitflyer::Cli::TerminalText.escape(execution.values_at(*FIELDS).join(' | ')) }
    puts HEADER, rows
  ensure
    close_persistent_http_client
  end

  private

  def fetch_executions(filters)
    response = persistent_http_client.executions(product_code: 'FX_BTC_JPY', count: PAGE_SIZE, **filters)
    return response if response.is_a?(Array) && response.all? { |execution| complete_execution?(execution) }

    message = response['error_message'].to_s if response.is_a?(Hash)
    detail = message.to_s.empty? ? 'Unexpected response from bitFlyer.' : message
    raise LookupFailed, "Could not list executions. #{Bitflyer::Cli::TerminalText.escape(detail)}"
  rescue Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, SocketError, SystemCallError, IOError, Timeout::Error,
         OpenSSL::SSL::SSLError, TypeError => e
    raise LookupFailed, "Could not list executions. #{Bitflyer::Cli::TerminalText.escape(e.message)}"
  end

  def complete_execution?(execution)
    return false unless execution.is_a?(Hash)

    execution.values_at(*FIELDS).all? { |value| !value.nil? && !(value.is_a?(String) && value.strip.empty?) }
  end
end
