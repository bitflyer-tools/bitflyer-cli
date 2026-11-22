# frozen_string_literal: true

require 'pathname'
require 'thor'

module Bitflyer
  module Cli
    module SubmissionStateDirectory
      def self.prepare(directory)
        raise Thor::Error, "Unsafe submission state directory: #{directory}" if directory.split('/').include?('..')

        leaf = Pathname.new(File.absolute_path(directory))
        leaf.ascend.to_a.reverse_each do |path|
          stat = directory_stat(path)
          next if trusted?(stat, path == leaf)

          raise Thor::Error, "Unsafe submission state directory: #{path}"
        end
      rescue SystemCallError => e
        raise Thor::Error, "Could not prepare submission state directory: #{e.message}"
      end

      def self.directory_stat(path)
        File.lstat(path)
      rescue Errno::ENOENT
        begin
          Dir.mkdir(path, 0o700)
        rescue Errno::EEXIST
          # Another process may have created the entry. Validate it below.
        end
        File.lstat(path)
      end

      def self.trusted?(stat, leaf)
        return false unless stat.directory?
        return stat.uid == Process.euid && stat.mode.nobits?(0o022) if leaf

        # The sticky bit protects trusted child entries in shared directories such as /tmp.
        [0, Process.euid].include?(stat.uid) && (stat.mode.nobits?(0o022) || stat.sticky?)
      end

      private_class_method :directory_stat, :trusted?
    end
  end
end
