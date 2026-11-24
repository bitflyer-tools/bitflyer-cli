# frozen_string_literal: true

require 'bitflyer/cli/active_stop_classifier'

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
        return if SKIPPED.include?(ActiveStopClassifier.from_list(order, side))

        parameter = @classifier.resolve(order)
        return unless parameter && parameter['side'] == side

        @stop.all? { |key, value| parameter[key.to_s] == value } ? :exact : :conflict
      end
    end
  end
end
