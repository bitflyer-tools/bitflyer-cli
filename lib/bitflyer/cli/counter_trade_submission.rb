# frozen_string_literal: true

require 'digest'
require 'json'
require 'thor'
require 'bitflyer/cli/durable_file'
require 'bitflyer/cli/submission_state_directory'

module Bitflyer
  module Cli
    class CounterTradeSubmission
      def self.state_directory
        SubmissionStateDirectory.under('counter-trades')
      end

      def initialize(product_code, api_key)
        @path = File.join(self.class.state_directory, "#{product_code}.json")
        @credential = Digest::SHA256.hexdigest(api_key.to_s)
      end

      def synchronize(&)
        SubmissionStateDirectory.synchronize(@path, "#{@path}.lock", "Could not lock counter trade: #{@path}", &)
      end

      def pending
        record = JSON.parse(File.read(@path, mode: File::RDONLY | File::NOFOLLOW))
        if !record.is_a?(Hash) || record['credential'] != @credential
          require_reconciliation('Use the original API key to reconcile the previous counter trade.')
        end
        record
      rescue Errno::ENOENT
        nil
      rescue JSON::ParserError
        require_reconciliation('Could not read the previous counter trade record.')
      end

      def record(exposure, acceptance_id = nil)
        value = JSON.generate(credential: @credential, exposure: exposure.to_s('F'), acceptance_id: acceptance_id)
        DurableFile.replace(@path, value)
      end

      def clear
        File.unlink(@path)
      end

      def require_reconciliation(message)
        raise Thor::Error, "#{message}\nCheck the order and exposure in bitFlyer before retrying. " \
                           "If manual reconciliation is needed, see the counter_trade instructions. Record: #{@path}"
      end
    end
  end
end
