require 'socket'
require 'openssl'
require 'timeout'

class KeepAliveHTTPSServer
  attr_reader :requests, :certificate, :closed_connections

  def initialize(&reply)
    @requests = []
    @closed_connections = Queue.new
    @listener = TCPServer.new('127.0.0.1', 0)
    context = tls_context
    @worker = Thread.new { serve(OpenSSL::SSL::SSLServer.new(@listener, context), &reply) }
  end

  def url
    "https://127.0.0.1:#{@listener.addr[1]}"
  end

  def stop
    @worker.kill.join
  ensure
    @listener.close
  end

  private

  def tls_context
    key = OpenSSL::PKey::RSA.new(2048)
    @certificate = OpenSSL::X509::Certificate.new
    @certificate.version = 2
    @certificate.serial = 1
    @certificate.subject = @certificate.issuer = OpenSSL::X509::Name.parse('/CN=127.0.0.1')
    @certificate.public_key = key.public_key
    @certificate.not_before = Time.now - 60
    @certificate.not_after = Time.now + 3600
    @certificate.add_extension(OpenSSL::X509::ExtensionFactory.new.create_extension('subjectAltName', 'IP:127.0.0.1'))
    @certificate.sign(key, OpenSSL::Digest.new('SHA256'))
    OpenSSL::SSL::SSLContext.new.tap do |context|
      context.cert = @certificate
      context.key = key
    end
  end

  def serve(server, &reply)
    connection = 0
    loop do
      socket = server.accept
      connection += 1
      serve_connection(socket, connection, &reply)
    end
  end

  def serve_connection(socket, connection)
    while (line = socket.gets)
      method, path = line.split
      headers = read_headers(socket)
      body = socket.read(headers.fetch('content-length', '0').to_i)
      @requests << [connection, method, path, headers, body]
      response, close, status, response_headers = yield(path, @requests.size)
      break unless response

      payload = response.is_a?(String) ? response : JSON.generate(response)
      extra_headers = response_headers&.map { |key, value| "#{key}: #{value}\r\n" }&.join
      socket.write("HTTP/1.1 #{status || '200 OK'}\r\nContent-Length: #{payload.bytesize}\r\n" \
                   "Connection: #{close ? 'close' : 'keep-alive'}\r\n#{extra_headers}\r\n#{payload}")
      break if close
    end
  ensure
    socket.close
    @closed_connections << connection
  end

  def read_headers(socket)
    {}.tap do |headers|
      while (line = socket.gets) && line != "\r\n"
        key, value = line.split(':', 2)
        headers[key.downcase] = value.strip
      end
    end
  end
end
