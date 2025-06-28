# frozen_string_literal: true

module Authorization
  def api_key
    ENV['BITFLYER_API_KEY'] || puts('environment variable BITFLYER_API_KEY is not set')
  end

  def api_secret
    ENV['BITFLYER_API_SECRET'] || puts('environment variable BITFLYER_API_SECRET is not set')
  end
end
