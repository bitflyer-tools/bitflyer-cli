# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'
require 'bitflyer/cli/terminal_text'

class OpenOrdersCommand
  include HasHTTPClient

  class LookupFailed < StandardError; end

  def run
    children = http_private_client.child_orders(product_code: 'FX_BTC_JPY', child_order_state: 'ACTIVE')
    child_rows = order_rows(children, 'child') { |order| child_row(order) }
    parents = http_private_client.parent_orders(product_code: 'FX_BTC_JPY', parent_order_state: 'ACTIVE')
    parent_rows = order_rows(parents, 'parent') { |order| parent_row(order) }

    print_orders('Child orders', 'Order ID | Type | Side | Price (JPY) | Remaining size (BTC)', child_rows)
    print_orders('Parent strategies', 'Order ID | Strategy type | Order date', parent_rows)
  end

  private

  def order_rows(orders, type, &)
    id_key = "#{type}_order_id"
    return orders.map(&) if orders.is_a?(Array) && orders.all? { |order| valid_order?(order, id_key) }

    message = orders['error_message'].to_s if orders.is_a?(Hash)
    detail = message.to_s.empty? ? 'Unexpected response from bitFlyer.' : message
    raise LookupFailed, "Could not list #{type} orders. #{Bitflyer::Cli::TerminalText.escape(detail)}"
  end

  def valid_order?(order, id_key)
    return false unless order.is_a?(Hash)

    id = order[id_key]
    id.is_a?(String) && !id.strip.empty?
  end

  def child_row(order)
    fields = order.values_at('child_order_id', 'child_order_type', 'side', 'price', 'outstanding_size')
    Bitflyer::Cli::TerminalText.escape(fields.join(' | '))
  end

  def parent_row(order)
    fields = order.values_at('parent_order_id', 'parent_order_type', 'parent_order_date')
    Bitflyer::Cli::TerminalText.escape(fields.join(' | '))
  end

  def print_orders(title, header, rows)
    puts title
    puts(rows.empty? ? 'None.' : [header, *rows])
  end
end
