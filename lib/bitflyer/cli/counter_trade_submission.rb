# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'thor'
require 'bitflyer/cli/durable_file'

module Bitflyer
  module Cli
    class CounterTradeSubmission
      def self.state_directory
        root = ENV.fetch('XDG_STATE_HOME', nil)
        root = File.expand_path('~/.local/state') if root.to_s.empty?
        File.join(root, 'bitflyer-cli', 'counter-trades')
      end

      def initialize(product_code, api_key)
        @path = File.join(self.class.state_directory, "#{product_code}.json")
        @credential = Digest::SHA256.hexdigest(api_key.to_s)
      end

      def synchronize
        FileUtils.mkdir_p(File.dirname(@path), mode: 0o700)
        File.open("#{@path}.lock", File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
          raise IOError, "Could not lock counter trade: #{@path}" unless lock.flock(File::LOCK_EX)

          yield
        end
      end

      def pending
        record = JSON.parse(File.read(@path))
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
