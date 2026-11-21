if ENV['COVERAGE'] == 'true'
  require 'simplecov'

  SimpleCov.start do
    cover 'lib/**/*.rb'
    merging false
    history_limit 0
    coverage :line, minimum: 95
  end
end

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'bitflyer/cli'

Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |file| require file }

RSpec.configure do |config|
  config.include ClientDoubles

  config.around(:each, :stop_state) do |example|
    Dir.mktmpdir do |directory|
      @stop_state_directory = directory
      example.run
    end
  end

  config.before(:each, :stop_state) do
    allow(Bitflyer::Cli::StopSubmission).to receive(:state_directory).and_return(@stop_state_directory)
  end

  config.before do
    allow(Net::HTTP).to receive(:start).and_raise('HTTP requests are not allowed in specs')
    allow(WebSocket::Client::Simple).to receive(:connect).and_raise('WebSocket connections are not allowed in specs')
  end
end
