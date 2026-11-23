# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'bitflyer/cli/durable_file'
require 'bitflyer/cli/order_rejected'

module Bitflyer
  module Cli
    class StopSubmission
      class Unverified < StandardError; end

      UNVERIFIED = 'unverified'
      COMPLETED_PREFIX = 'completed:'
      LOCK_COUNT = 64
      # Preserve the field order used by existing records and lock slots.
      IDENTITY_FIELDS = %i[product_code condition_type side trigger_price size].freeze

      attr_reader :path

      def self.state_directory
        root = ENV.fetch('XDG_STATE_HOME', nil)
        root = File.expand_path('~/.local/state') if root.to_s.empty?
        File.join(root, 'bitflyer-cli', 'stops')
      end

      def initialize(api_key, stop)
        key = Digest::SHA256.hexdigest([api_key, *stop.values_at(*IDENTITY_FIELDS)].to_json)
        directory = self.class.state_directory
        @path = File.join(directory, key)
        @lock_path = File.join(directory, "slot-#{key.to_i(16) % LOCK_COUNT}.lock")
      end

      def synchronize
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        File.open(@lock_path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
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
        case OrderRejected.classify(response, acceptance_key)
        when :accepted
          record(response.body.fetch(acceptance_key))
        when :rejected
          clear
          OrderRejected.raise_rejection!(response.body)
        else
          raise_unverified("Could not verify stop order acceptance (HTTP #{response.status}).")
        end
      end

      def clear
        File.unlink(@path)
      end
    end
  end
end
