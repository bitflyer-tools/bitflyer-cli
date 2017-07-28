require 'thor'
require 'bitflyer/cli/command/summary_command'

module Bitflyer
  class CLI < Thor
    desc 'summary', 'show current balance information'
    def summary
      SummaryCommand.new.run
    end
  end
end
