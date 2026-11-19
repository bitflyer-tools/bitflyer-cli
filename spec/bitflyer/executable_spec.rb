require 'spec_helper'
require 'open3'

describe 'bitflyer executable' do
  let(:private_client) { stub_private_client }

  def run_bitflyer(*args)
    Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/bitflyer', *args, chdir: File.expand_path('../..', __dir__))
  end

  def run_cancel_all
    stub_const('ARGV', ['cancel_all'])
    load File.expand_path('../../exe/bitflyer', __dir__)
  end

  it 'exits unsuccessfully when a required option is missing' do
    _, stderr, status = run_bitflyer('order_by_best', '-a', '0.01')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to match(/required options.*--type/)
  end

  it 'exits unsuccessfully for a fractional TWAP order count' do
    _, stderr, status = run_bitflyer('order_by_twap', '-a', '0.01', '-t', 'buy', '-n', '1.9', '-i', '0')

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('--number-of-times must be a whole number')
  end

  it 'exits successfully when displaying help' do
    stdout, stderr, status = run_bitflyer('help', 'order_by_best')

    expect(status).to be_success
    expect(stdout).to include('order_by_best')
    expect(stderr).to be_empty
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
