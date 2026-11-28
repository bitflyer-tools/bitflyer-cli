# frozen_string_literal: true

require 'json'
require 'bitflyer/cli/persistent_http_client'
require 'bitflyer/cli/terminal_text'

class CancellationClient
  Result = Data.define(:outcome, :http_code, :exchange_status, :message) do
    def unverified_http_status?
      http_code == '408' || http_code.to_i.between?(500, 599)
    end

    def failure_message(unverified_prefix, rejected_fallback)
      case outcome
      when :rejected
        message.to_s.empty? ? rejected_fallback : message
      when :unverified
        http_code ? "#{unverified_prefix} (HTTP #{http_code})." : "#{unverified_prefix}."
      end
    end
  end

  def initialize(key, secret)
    @client = Bitflyer::Cli::PersistentHTTPClient.new(key, secret)
  end

  def post(path, params)
    classify(@client.cancel(path, params))
  rescue *Bitflyer::Cli::PersistentHTTPClient::COMMUNICATION_ERRORS
    Result.new(:unverified, nil, nil, nil)
  ensure
    @client.close
  end

  private

  def classify(response)
    code = response.code
    body = response.body.to_s
    return Result.new(:accepted, code, nil, nil) if code == '200' && body.empty?

    unverified = Result.new(:unverified, code, nil, nil)
    return unverified if unverified.unverified_http_status?

    error = parse_error(body)
    status = error['status']
    return unverified unless status.is_a?(Integer) && status.negative?

    Result.new(:rejected, code, status, Bitflyer::Cli::TerminalText.escape(error['error_message'].to_s))
  end

  def parse_error(body)
    parsed = JSON.parse(body)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
end
