# frozen_string_literal: true

require 'digest'
require 'json'
require 'pathname'
require 'tempfile'
require 'thor'
require 'bitflyer/cli/submission_state_directory'

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
        SubmissionStateDirectory.prepare(File.dirname(@path))
        File.open("#{@path}.lock", File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
          raise IOError, "Could not lock counter trade: #{@path}" unless lock.flock(File::LOCK_EX)

          yield
        end
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
        directory = File.dirname(@path)
        Tempfile.create('pending-', directory) do |file|
          file.write(JSON.generate(credential: @credential, exposure: exposure.to_s('F'), acceptance_id: acceptance_id))
          file.flush
          file.fsync
          File.rename(file.path, @path)
          sync_directory_tree(directory)
        end
      end

      def clear
        File.unlink(@path)
      end

      def require_reconciliation(message)
        raise Thor::Error, "#{message}\nCheck the order and exposure in bitFlyer before retrying. " \
                           "If manual reconciliation is needed, see the counter_trade instructions. Record: #{@path}"
      end

      private

      def sync_directory_tree(directory)
        # An existing ancestor may have been created by an interrupted or concurrent run.
        Pathname.new(File.realpath(directory)).ascend do |path|
          File.open(path.to_s, File::RDONLY, &:fsync)
        end
      end
    end
  end
end
