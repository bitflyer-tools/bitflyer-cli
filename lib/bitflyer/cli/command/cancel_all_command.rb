require 'bitflyer'
require 'bitflyer/cli/authorization'

class CancelAllCommand
  include Authorization

  def initialize
    @http_client = Bitflyer.http_private_client(api_key, api_secret)
  end

  def run
    @http_client.cancel_all_child_orders(product_code: 'FX_BTC_JPY')
  end
end
