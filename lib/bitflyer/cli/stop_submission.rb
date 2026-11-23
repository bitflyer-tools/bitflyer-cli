# frozen_string_literal: true

require 'bigdecimal'
require 'digest'
require 'fileutils'
require 'json'
require 'thor'
require 'bitflyer/cli/durable_file'
require 'bitflyer/cli/order_rejected'
require 'bitflyer/cli/parent_order_lookup'

module Bitflyer
  module Cli
    class StopSubmission
      class Unverified < StandardError; end

      UNVERIFIED = 'unverified'
      COMPLETED_PREFIX = 'completed:'
      LOCK_COUNT = 64
      HISTORY_REQUEST_LIMIT = 10
      TERMINAL_STATES = %w[CANCELED EXPIRED REJECTED COMPLETED].freeze
      ACCEPTANCE_ID = 'parent_order_acceptance_id'
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

      def reconcile(acceptance_id, lookup)
        return [acceptance_id, nil] if acceptance_id == UNVERIFIED
        if acceptance_id.start_with?(COMPLETED_PREFIX)
          return [acceptance_id.delete_prefix(COMPLETED_PREFIX), 'COMPLETED']
        end

        state = terminal_state(acceptance_id, lookup)
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

      def terminal_state(pending, lookup)
        state, order = lookup.find_across_states(TERMINAL_STATES, max_requests: HISTORY_REQUEST_LIMIT) do |entry|
          entry[ACCEPTANCE_ID] == pending
        end
        confirm_zero_fill!(order, state, pending) if order && state != 'COMPLETED'
        state
      rescue ParentOrderLookup::RequestLimitExceeded
        raise Thor::Error, "Stop order #{pending} still requires reconciliation after " \
                           "#{HISTORY_REQUEST_LIMIT} history requests. Submission record: #{path}"
      end

      def confirm_zero_fill!(order, state, pending)
        executed_size = BigDecimal(order['executed_size'].to_s, exception: false)
        return if executed_size&.zero?

        detail = if executed_size&.finite? && executed_size.positive?
                   "executed #{executed_size.to_s('F')} BTC. Wait for the position to reflect the fill before retrying."
                 else
                   'has an unconfirmed executed size. Check the order in bitFlyer before retrying.'
                 end
        raise Thor::Error, "Previous stop order (#{pending}, #{state}) #{detail} Submission record: #{path}"
      end

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
