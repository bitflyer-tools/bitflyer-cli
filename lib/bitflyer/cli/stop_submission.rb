# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'tempfile'
require 'bitflyer/cli/order_rejected'

module Bitflyer
  module Cli
    class StopSubmission
      class Unverified < StandardError; end

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

      def record_response(response, acceptance_key)
        status = response.status
        body = response.body
        acceptance_id = body[acceptance_key] if body.is_a?(Hash)
        if acceptance_id.nil? && definite_rejection?(status, body)
          clear
          OrderRejected.check!(body, acceptance_key)
        end
        return record(acceptance_id) if status.between?(200, 299) &&
                                        acceptance_id.is_a?(String) && !acceptance_id.strip.empty?

        raise Unverified, "Could not verify stop order acceptance (HTTP #{status})."
      end

      def clear
        File.unlink(@path)
      end

      private

      def definite_rejection?(status, body)
        verifiable = status.between?(200, 299) || (status.between?(400, 499) && status != 408)
        verifiable && body.is_a?(Hash) && body['status'].is_a?(Integer) && body['status'].negative?
      end
    end
  end
end
