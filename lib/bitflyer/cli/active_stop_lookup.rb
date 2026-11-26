# frozen_string_literal: true

require 'bitflyer/cli/stop_order_matcher'

module Bitflyer
  module Cli
    class ActiveStopLookup
      def initialize(client, lookup)
        @client = client
        @lookup = lookup
      end

      def find(stop)
        matcher = StopOrderMatcher.new(@client, stop)
        conflicts = []
        exact = @lookup.find('ACTIVE') do |entry|
          match = matcher.classify(entry)
          next false unless match
          next true if match == :exact

          conflicts << entry.fetch('parent_order_id')
          false
        end
        [exact, conflicts]
      end
    end
  end
end
