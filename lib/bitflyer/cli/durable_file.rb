# frozen_string_literal: true

require 'pathname'
require 'tempfile'

module Bitflyer
  module Cli
    module DurableFile
      module_function

      def replace(path, value)
        directory = File.dirname(path)
        Tempfile.create('pending-', directory) do |file|
          file.write(value)
          file.flush
          file.fsync
          File.rename(file.path, path)
          sync_directory_tree(directory)
        end
      end

      def sync_directory_tree(directory)
        # An existing ancestor may have been created by an interrupted or concurrent run.
        Pathname.new(File.realpath(directory)).ascend do |path|
          File.open(path.to_s, File::RDONLY, &:fsync)
        end
      end

      private_class_method :sync_directory_tree
    end
  end
end
