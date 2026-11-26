# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'bitflyer/cli/persistent_http_client'

module Bitflyer
  module Cli
    # Fires a one-shot webhook notification the moment a watched price or balance
    # threshold is crossed, instead of on every poll while the condition holds.
    class AlertNotifier
      def initialize(webhook_url:, alert_price: nil, alert_balance: nil)
        @webhook_url = webhook_url
        @alert_price = alert_price
        @alert_balance = alert_balance
        @price_side = nil
        @balance_side = nil
      end

      def check(price:, balance:)
        check_price(price)
        check_balance(balance)
      end

      private

      def check_price(price)
        return unless @alert_price && price

        side = price >= @alert_price ? :above : :below
        @price_home_side ||= side
        departing_home = @price_side == @price_home_side && side != @price_home_side
        notify("Price alert: #{price} crossed #{@alert_price}") if departing_home
        @price_side = side
      end

      def check_balance(balance)
        return unless @alert_balance && balance

        side = balance >= @alert_balance ? :above : :below
        notify("Balance alert: #{balance} dropped below #{@alert_balance}") if @balance_side == :above && side == :below
        @balance_side = side
      end

      def notify(message)
        uri = URI(@webhook_url)
        request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        request.body = JSON.generate(text: message, content: message)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(request) }
      rescue *Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS => e
        warn "Failed to send alert webhook: #{e.message}"
      end
    end
  end
end
