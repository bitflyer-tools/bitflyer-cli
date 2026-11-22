# frozen_string_literal: true

require 'digest'
require 'json'
require 'bitflyer/cli/durable_file'
require 'bitflyer/cli/order_rejected'
require 'bitflyer/cli/submission_state_directory'

module Bitflyer
  module Cli
    class StopSubmission
      class Unverified < StandardError; end

      UNVERIFIED = 'unverified'
      COMPLETED_PREFIX = 'completed:'

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
        SubmissionStateDirectory.prepare(File.dirname(@path))
        File.open("#{@path}.lock", File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
          raise IOError, "Could not lock stop submission: #{@path}" unless lock.flock(File::LOCK_EX)

          yield
        end
      end

      def pending
        value = File.read(@path, mode: File::RDONLY | File::NOFOLLOW)
        value.strip.empty? ? UNVERIFIED : value
      rescue Errno::ENOENT
        nil
      end

      def reconcile(acceptance_id)
        return [acceptance_id, nil] if acceptance_id == UNVERIFIED
        if acceptance_id.start_with?(COMPLETED_PREFIX)
          return [acceptance_id.delete_prefix(COMPLETED_PREFIX), 'COMPLETED']
        end

        state = yield
        record("#{COMPLETED_PREFIX}#{acceptance_id}") if state == 'COMPLETED'
        clear if state && state != 'COMPLETED'
        [acceptance_id, state]
      end

      def submit(acceptance_key, &)
        record(UNVERIFIED)
        record_response(receive_response(&), acceptance_key)
      end

      def raise_unverified(message)
        raise Unverified, "#{message}\nCheck the order in bitFlyer before retrying. " \
                          "Once you confirm the outcome, remove the unverified submission record at:\n#{path}"
      end

      private

      def receive_response
        yield
      rescue Timeout::Error, SocketError, SystemCallError, IOError,
             OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
        raise_unverified('Could not verify stop order acceptance due to a communication error.')
      end

      def record(value)
        DurableFile.replace(@path, value)
      end

      def record_response(response, acceptance_key)
        status = response.status
        body = response.body
        acceptance_id = body[acceptance_key] if body.is_a?(Hash)
        if acceptance_id.nil? && definite_rejection?(status, body)
          clear
          OrderRejected.check!(body, acceptance_key)
        end
        return record(acceptance_id) if OrderRejected.accepted?(status, acceptance_id, body)

        raise_unverified("Could not verify stop order acceptance (HTTP #{status}).")
      end

      def clear
        File.unlink(@path)
      end

      def definite_rejection?(status, body)
        verifiable = status.between?(200, 299) || (status.between?(400, 499) && status != 408)
        verifiable && body.is_a?(Hash) && body['status'].is_a?(Integer) && body['status'].negative?
      end
    end
  end
end
