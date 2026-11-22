# frozen_string_literal: true

require 'spec_helper'

describe Bitflyer::Cli::StopSubmission, :stop_state do
  subject(:submission) { described_class.new('api-key', { side: 'SELL', trigger_price: 995_000, size: 0.2 }) }

  ['unverified', 'JRF20180101-000000-000001', 'completed:JRF20180101-000000-000001'].each do |value|
    it "reads an existing #{value.inspect} record" do
      File.write(submission.path, value)

      expect(submission.pending).to eq(value)
    end
  end
end
