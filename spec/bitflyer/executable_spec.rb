require 'spec_helper'

describe 'bitflyer executable' do
  let(:private_client) { stub_private_client }

  def run_cancel_all
    stub_const('ARGV', ['cancel_all'])
    load File.expand_path('../../exe/bitflyer', __dir__)
  end

  it 'prints a cancel-all rejection to stderr and exits unsuccessfully' do
    stub_responses(private_client, cancel_all_child_orders: { 'status' => -200, 'error_message' => 'rejected' })

    expect do
      expect { run_cancel_all }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output("rejected\n").to_stderr
  end

  it 'completes normally when the cancellation is accepted' do
    stub_responses(private_client, cancel_all_child_orders: '')

    expect { run_cancel_all }.to output('').to_stderr
  end
end
