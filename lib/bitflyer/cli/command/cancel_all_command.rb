# frozen_string_literal: true

require 'bitflyer/cli/has_http_client'

class CancelAllCommand
  include HasHTTPClient

  def run
    http_private_client.cancel_all_child_orders(product_code: 'FX_BTC_JPY')
  end
end
