# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tempfile'

module Bitflyer
  module Cli
    class StopSubmission
      UNVERIFIED = 'unverified'

      attr_reader :path

      def self.state_directory
        root = ENV.fetch('XDG_STATE_HOME', nil)
        root = File.expand_path('~/.local/state') if root.to_s.empty?
        File.join(root, 'bitflyer-cli', 'stops')
      end

      def initialize(api_key, stop)
        key = Digest::SHA256.hexdigest([api_key, *stop.values].to_json)
        @path = File.join(self.class.state_directory, key)
      end

      def synchronize
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        File.open("#{@path}.lock", File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
          raise IOError, "Could not lock stop submission: #{@path}" unless lock.flock(File::LOCK_EX)

          yield
        end
      end

      def pending
        value = File.read(@path)
        value.strip.empty? ? UNVERIFIED : value
      rescue Errno::ENOENT
        nil
      end

      def record(value)
        Tempfile.create('pending-', File.dirname(@path)) do |file|
          file.write(value)
          file.flush
          file.fsync
          File.rename(file.path, @path)
        end
      end

      def clear
        File.unlink(@path)
      end
    end
  end
end
