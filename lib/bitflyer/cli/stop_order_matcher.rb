# frozen_string_literal: true

require 'bitflyer/cli/active_stop_classifier'
require 'bitflyer/cli/model/position'

module Bitflyer
  module Cli
    class StopOrderMatcher
      SKIPPED = %i[not_stop opposite_side].freeze

      def initialize(client, stop)
        @stop = stop
        @classifier = ActiveStopClassifier.new(client, stop.fetch(:product_code))
      end

      def classify(order)
        side = @stop.fetch(:side)
        classification = ActiveStopClassifier.from_list(order, side)
        return if SKIPPED.include?(classification)
        return :conflict if classification == :same_side && different_size?(order['size'])

        parameter = @classifier.resolve(order)
        return unless parameter && parameter['side'] == side

        exact_match?(parameter) ? :exact : :conflict
      end

      private

      def exact_match?(parameter)
        @stop.all? { |key, value| parameter[key.to_s] == value }
      end

      def different_size?(size)
        raw = size.to_s
        return false unless Position::DECIMAL.match?(raw)

        listed_size = Float(raw, exception: false)
        listed_size&.finite? && listed_size.positive? && listed_size != @stop.fetch(:size)
      end
    end
  end
end
