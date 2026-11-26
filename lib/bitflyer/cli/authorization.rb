# frozen_string_literal: true

module Authorization
  class MissingCredentials < StandardError; end

  def api_key
    ENV.fetch('BITFLYER_API_KEY', nil)
  end

  def api_secret
    ENV.fetch('BITFLYER_API_SECRET', nil)
  end

  private

  def private_credentials
    credentials = { 'BITFLYER_API_KEY' => api_key, 'BITFLYER_API_SECRET' => api_secret }
    missing = credentials.select { |_, value| value.nil? }.keys
    raise MissingCredentials, "Set the required environment variables: #{missing.join(', ')}" unless missing.empty?

    credentials.values
  end
end
