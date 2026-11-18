# frozen_string_literal: true

require 'bitflyer/cli/realtime_client'

module HasRealtimeClient
  def realtime_client
    @realtime_client ||= Bitflyer::Cli::RealtimeClient.new
  end
end
