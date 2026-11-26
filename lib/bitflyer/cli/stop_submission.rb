# frozen_string_literal: true

require 'bigdecimal'
require 'digest'
require 'json'
require 'thor'
require 'bitflyer/cli/durable_file'
require 'bitflyer/cli/order_rejected'
require 'bitflyer/cli/parent_order_lookup'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/submission_state_directory'

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
        SubmissionStateDirectory.under('stops')
      end

      def initialize(api_key, stop)
        key = Digest::SHA256.hexdigest([api_key, *stop.values_at(*IDENTITY_FIELDS)].to_json)
        directory = self.class.state_directory
        @path = File.join(directory, key)
        @lock_path = File.join(directory, "slot-#{key.to_i(16) % LOCK_COUNT}.lock")
      end

      def synchronize(&)
        SubmissionStateDirectory.synchronize(@path, @lock_path, "Could not lock stop submission: #{@path}", &)
      end

      def pending
        value = File.read(@path, mode: File::RDONLY | File::NOFOLLOW)
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
        matches_pending = ->(entry) { entry[ACCEPTANCE_ID] == pending }
        state, order = lookup.find_across_states(TERMINAL_STATES, max_requests: HISTORY_REQUEST_LIMIT, &matches_pending)
        confirm_zero_fill!(order, state, pending) if order && state != 'COMPLETED'
        state
      rescue ParentOrderLookup::RequestLimitExceeded
        raise Thor::Error, "Stop order #{pending} still requires reconciliation after " \
                           "#{HISTORY_REQUEST_LIMIT} history requests. Submission record: #{path}"
      rescue *PersistentHTTPClient::COMMUNICATION_ERRORS => e
        raise ParentOrderLookup::LookupFailed,
              "Failed to look up terminal parent orders: #{e.message}. Submission record: #{path}"
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
