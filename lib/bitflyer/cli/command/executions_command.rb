# frozen_string_literal: true

require 'csv'
require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/terminal_text'

class ExecutionsCommand
  include HasHTTPClient

  class LookupFailed < StandardError; end

  PAGE_SIZE = 100
  MAX_PAGES = 1_000
  HEADER = 'Execution time | Side | Price (JPY) | Size (BTC) | Commission | Child order ID | Acceptance ID'
  CSV_HEADER = ['Execution time', 'Side', 'Price (JPY)', 'Size (BTC)', 'Commission', 'Child order ID',
                'Acceptance ID'].freeze
  FIELDS = %w[exec_date side price size commission child_order_id child_order_acceptance_id].freeze

  def run(child_order_id: nil, child_order_acceptance_id: nil, all: false, export: nil)
    if child_order_id && child_order_acceptance_id
      raise LookupFailed, 'Specify only one of --child-order-id and --child-order-acceptance-id.'
    end

    filters = { child_order_id: child_order_id, child_order_acceptance_id: child_order_acceptance_id }.compact
    executions = all ? fetch_all_executions(filters) : fetch_executions(filters)
    return puts 'No executions found.' if executions.empty?

    export ? export_csv(executions, export) : print_table(executions)
  ensure
    close_persistent_http_client
  end

  private

  def print_table(executions)
    rows = executions.map { |execution| Bitflyer::Cli::TerminalText.escape(execution.values_at(*FIELDS).join(' | ')) }
    puts HEADER, rows
  end

  def export_csv(executions, path)
    CSV.open(path, 'w') do |csv|
      csv << CSV_HEADER
      executions.each { |execution| csv << execution.values_at(*FIELDS) }
    end
    puts "Exported #{executions.size} execution#{'s' unless executions.size == 1} to #{path}."
  end

  def fetch_executions(filters)
    response = executions_page(filters)
    return response if response.is_a?(Array) && response.all? { |execution| complete_execution?(execution) }

    raise_lookup_failed(response)
  end

  def fetch_all_executions(filters)
    executions = []
    before = nil
    MAX_PAGES.times do
      page = executions_page(filters.merge(before: before).compact)
      raise_lookup_failed(page) unless page.is_a?(Array) && page.all? { |execution| complete_execution?(execution) }

      executions.concat(page)
      return executions if page.size < PAGE_SIZE

      before = next_cursor(page, before)
    end
    raise LookupFailed, "Could not list executions. Exceeded the #{MAX_PAGES}-page request limit."
  end

  def next_cursor(page, before)
    ids = page.map { |execution| execution['id'] }
    if ids.all? { |id| id.is_a?(Integer) && id.positive? }
      cursor = ids.min
      return cursor if before.nil? || cursor < before
    end

    raise LookupFailed, 'Could not paginate account executions.'
  end

  def executions_page(filters)
    persistent_http_client.executions(product_code: 'FX_BTC_JPY', count: PAGE_SIZE, **filters)
  rescue Bitflyer::Cli::PersistentHTTPClient::GetResponseError => e
    raise_lookup_failed(e.body, fallback: e.message)
  rescue *Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS, Net::ProtocolError, TypeError => e
    raise_lookup_failed(nil, fallback: e.message)
  end

  def raise_lookup_failed(response, fallback: 'Unexpected response from bitFlyer.')
    message = response['error_message'].to_s if response.is_a?(Hash)
    detail = message.to_s.empty? ? fallback : message
    raise LookupFailed, "Could not list executions. #{Bitflyer::Cli::TerminalText.escape(detail)}"
  end

  def complete_execution?(execution)
    return false unless execution.is_a?(Hash)

    execution.values_at(*FIELDS).all? { |value| !value.nil? && !(value.is_a?(String) && value.strip.empty?) }
  end
end
