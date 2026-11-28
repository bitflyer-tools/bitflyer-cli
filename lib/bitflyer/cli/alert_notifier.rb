# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'bitflyer/cli/persistent_http_client'

module Bitflyer
  module Cli
    # Detects threshold crossings and sends the resulting webhook notifications.
    class AlertNotifier
      class InvalidWebhookURL < StandardError; end

      def initialize(webhook_url:, alert_price: nil, alert_balance: nil)
        @webhook_uri = parse_webhook_url(webhook_url)
        @alert_price = alert_price
        @alert_balance = alert_balance
        @price_side = nil
        @balance_side = nil
      end

      def check(price:, balance:, &enqueue)
        check_price(price, &enqueue)
        check_balance(balance, &enqueue)
      end

      def deliver(message)
        uri = @webhook_uri
        request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        request.body = JSON.generate(text: message, content: message)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(request) }
        status = response.code.to_i
        warn "Failed to send alert webhook: HTTP #{status}" unless status.between?(200, 299)
      rescue *PersistentHTTPClient::COMMUNICATION_ERRORS => e
        warn "Failed to send alert webhook: #{e.class}"
      end

      private

      def parse_webhook_url(url)
        uri = URI.parse(url)
        return uri if uri.is_a?(URI::HTTP) && !uri.hostname.to_s.empty? && uri.port.between?(1, 65_535)

        raise InvalidWebhookURL
      rescue URI::Error
        raise InvalidWebhookURL
      end

      def check_price(price)
        return unless @alert_price && price

        side = price >= @alert_price ? :above : :below
        yield("Price alert: #{price} crossed #{@alert_price}") if @price_side && side != @price_side
        @price_side = side
      end

      def check_balance(balance)
        return unless @alert_balance && balance

        side = balance >= @alert_balance ? :above : :below
        yield("Balance alert: #{balance} dropped below #{@alert_balance}") if @balance_side == :above && side == :below
        @balance_side = side
      end
    end
  end
end
