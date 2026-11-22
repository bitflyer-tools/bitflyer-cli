# frozen_string_literal: true

module Bitflyer
  module Cli
    module TerminalText
      def self.escape(text)
        text.gsub(/[[:cntrl:]]/) { |character| character.dump[1...-1] }
      end
    end
  end
end
