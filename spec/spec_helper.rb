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

  config.before do
    allow(Net::HTTP).to receive(:start).and_raise('HTTP requests are not allowed in specs')
    allow(WebSocket::Client::Simple).to receive(:connect).and_raise('WebSocket connections are not allowed in specs')
  end
end
