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

    it 'joins the XDG state home with bitflyer-cli and the given segments' do
      ENV['XDG_STATE_HOME'] = '/custom/state'

      expect(described_class.under('stops')).to eq('/custom/state/bitflyer-cli/stops')
    end

    it 'falls back to ~/.local/state when XDG_STATE_HOME is unset' do
      ENV['XDG_STATE_HOME'] = nil

      expect(described_class.under('counter-trades'))
        .to eq(File.join(File.expand_path('~/.local/state'), 'bitflyer-cli', 'counter-trades'))
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
