# frozen_string_literal: true

require 'bitflyer/cli/authorization'
require 'bitflyer/cli/cancellation_client'

class CancelAllCommand
  include Authorization

  class Rejected < StandardError; end

  UNVERIFIED = 'Could not verify cancel-all acceptance from bitFlyer'

  def run
    client = CancellationClient.new(*private_credentials)
    result = client.post('/v1/me/cancelallchildorders', product_code: 'FX_BTC_JPY')
    return if result.outcome == :accepted

    raise Rejected, failure_message(result)
  end

  private

  def failure_message(result)
    if result.outcome == :rejected
      return result.message.empty? ? "Cancel-all request rejected (status #{result.exchange_status})" : result.message
    end

    result.http_code ? "#{UNVERIFIED} (HTTP #{result.http_code})." : "#{UNVERIFIED}."
  end
end
