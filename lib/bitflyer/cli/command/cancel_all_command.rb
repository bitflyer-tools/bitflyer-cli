# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'

class CancelAllCommand
  include HasHTTPClient

  class Rejected < StandardError; end

  def run
    response = http_private_client.cancel_all_child_orders(product_code: 'FX_BTC_JPY')
    status = response['status'] if response.is_a?(Hash)
    return response unless status.is_a?(Integer) && status.negative?

    message = response['error_message'].to_s
    raise Rejected, message.empty? ? "Cancel-all request rejected (status #{status})" : message
  end
end
