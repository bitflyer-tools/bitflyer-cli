# frozen_string_literal: true

require 'spec_helper'

describe Bitflyer::Cli::SubmissionStateDirectory do
  describe '.under' do
    around do |example|
      original = ENV.fetch('XDG_STATE_HOME', nil)
      example.run
    ensure
      ENV['XDG_STATE_HOME'] = original
    end

    it 'selects the same absolute state directory from different working directories' do
      ENV['XDG_STATE_HOME'] = '/custom/state'

      Dir.mktmpdir do |directory|
        paths = [Dir.pwd, directory].map do |working_directory|
          Dir.chdir(working_directory) { described_class.under('stops') }
        end
        expect(paths).to all(eq('/custom/state/bitflyer-cli/stops'))
      end
    end

    { unset: nil, empty: '' }.each do |setting, value|
      it "falls back to ~/.local/state when XDG_STATE_HOME is #{setting}" do
        ENV['XDG_STATE_HOME'] = value

        expect(described_class.under('counter-trades'))
          .to eq(File.join(File.expand_path('~/.local/state'), 'bitflyer-cli', 'counter-trades'))
      end
    end
  end

  describe '.synchronize' do
    it 'prepares the parent directory and yields while holding the lock' do
      Dir.mktmpdir do |directory|
        path = File.join(directory, 'submissions', 'record')
        lock_path = File.join(directory, 'submissions', 'record.lock')
        yielded = false

        described_class.synchronize(path, lock_path, 'unavailable') { yielded = true }

        expect(yielded).to be(true)
        expect(File.directory?(File.dirname(path))).to be(true)
        expect(File).to exist(lock_path)
      end
    end

    it 'raises the given message without yielding when the lock cannot be acquired' do
      Dir.mktmpdir do |directory|
        path = File.join(directory, 'record')
        lock_path = File.join(directory, 'record.lock')
        lock = double('lock', flock: false)
        allow(File).to receive(:open).with(lock_path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600).and_yield(lock)

        expect { described_class.synchronize(path, lock_path, 'locked out') { raise 'should not run' } }
          .to raise_error(IOError, 'locked out')
      end
    end
  end
end
