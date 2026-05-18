# Low-level mTLS client that drives the TLS handshake manually
# so we can emit fine-grained events between each step:
#
#   tcp_connecting -> tcp_connected
#                  -> tls_handshake_starting
#                  -> tls_handshake_completed  (or tls_handshake_failed)
#                  -> http_response (or http_failed)
#
# We use OpenSSL::SSL::SSLSocket directly instead of Net::HTTP because Net::HTTP
# hides the TCP-vs-TLS distinction inside one call.

require 'socket'
require 'openssl'
require 'uri'
require 'json'
require_relative 'events'

class MtlsClient
  CERT_DIR = '/certs'        # fixtures de teste (wrong-ca, expired) gerados pela init container
  RUN_DIR  = '/run'          # cert ativo do step-ca (client.crt + client.key, rotacionados)
  STEP_DIR = '/step-data'    # root_ca.crt do step-ca (volume read-only)
  DATA_DIR = '/data'         # identidade do onboarding (efêmero)
  CA_FILE  = "#{STEP_DIR}/certs/root_ca.crt"

  # Lista os certs de cliente disponíveis (filtra pelo EKU clientAuth).
  def self.available_client_certs
    paths = (Dir.glob("#{RUN_DIR}/client.crt") +
             Dir.glob("#{CERT_DIR}/*.crt") +
             Dir.glob("#{DATA_DIR}/identity.crt")).sort
    paths.filter_map do |crt_path|
      cert = OpenSSL::X509::Certificate.new(File.read(crt_path))
      eku  = cert.extensions.find { |e| e.oid == 'extendedKeyUsage' }&.value.to_s
      next unless eku.include?('Client Authentication') || eku.include?('clientAuth')

      key_path = crt_path.sub(/\.crt$/, '.key')
      next unless File.exist?(key_path)

      cn = cert.subject.to_a.find { |k, _, _| k == 'CN' }&.dig(1)
      issuer_cn = cert.issuer.to_a.find { |k, _, _| k == 'CN' }&.dig(1)
      expired = Time.now > cert.not_after
      onboarding = crt_path.start_with?(DATA_DIR)
      step_ca    = crt_path.start_with?(RUN_DIR)
      label =
        if onboarding then "#{cn}.crt (onboarded)"
        elsif step_ca then "client.crt (step-ca, rota ↻)"
        else File.basename(crt_path)
        end
      {
        cert_path: crt_path,
        name: label,
        cn: cn,
        issuer_cn: issuer_cn,
        not_after: cert.not_after.utc.iso8601,
        expired: expired,
        source: onboarding ? 'onboarding' : (step_ca ? 'step-ca' : 'static')
      }
    rescue StandardError
      nil
    end
  end

  def initialize(api_url:)
    @api_url = api_url
  end

  # opts: { cert_path: '/certs/client.crt' } OR { no_cert: true }
  def run(opts = {})
    cfg = config_for(opts)
    Events.emit('request_started',
      mode: cfg[:client_cert] ? 'with-cert' : 'no-cert',
      cert_path: cfg[:client_cert],
      target: cfg[:url])

    uri = URI(cfg[:url])
    host = uri.host.delete('[]')   # IPv6 literals come wrapped in []
    port = uri.port

    # --- TCP ----------------------------------------------------------------
    Events.emit('tcp_connecting', host: host, port: port, family: :inet6)
    tcp = TCPSocket.new(host, port)
    peer = tcp.peeraddr   # [family, port, name, ip]
    Events.emit('tcp_connected', remote_ip: peer[3], remote_port: peer[1])

    # --- TLS ----------------------------------------------------------------
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
    ctx.ca_file = cfg[:ca_file]
    ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
    ctx.verify_hostname = true   # checa SAN contra ssl.hostname — fundamental no cenário wrong-host
    if cfg[:client_cert]
      ctx.cert = OpenSSL::X509::Certificate.new(File.read(cfg[:client_cert]))
      # PKey.read detecta o tipo (RSA / EC) automaticamente — step-ca emite EC P-256 por padrão.
      ctx.key  = OpenSSL::PKey.read(File.read(cfg[:client_key]))
    end

    ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
    ssl.hostname = cfg[:sni]   # SNI — also used by Ruby for hostname verification
    ssl.sync_close = true

    Events.emit('tls_handshake_starting',
      sni: cfg[:sni],
      presenting_client_cert: !cfg[:client_cert].nil?,
      client_cert_path: cfg[:client_cert],
      trusting_ca: cfg[:ca_file])

    begin
      ssl.connect
    rescue OpenSSL::SSL::SSLError => e
      Events.emit('tls_handshake_failed', error: e.message)
      ssl.close rescue nil
      return { ok: false, stage: 'tls', error: e.message }
    end

    server_cert = ssl.peer_cert
    Events.emit('tls_handshake_completed',
      protocol: ssl.ssl_version,
      cipher: ssl.cipher&.first,
      server_subject: server_cert&.subject&.to_s,
      server_issuer:  server_cert&.issuer&.to_s,
      verify_result:  ssl.verify_result)

    # --- HTTP (manual, very small) -----------------------------------------
    path = uri.path.empty? ? '/whoami' : uri.path
    req = "GET #{path} HTTP/1.1\r\nHost: #{cfg[:sni]}\r\nConnection: close\r\n\r\n"
    ssl.write(req)
    raw = ssl.read
    ssl.close

    head, _, body = raw.partition("\r\n\r\n")
    status = head.lines.first.to_s.split[1]&.to_i

    Events.emit('http_response', status: status, body_preview: body.to_s[0, 300])
    { ok: true, status: status, body: body }
  rescue StandardError => e
    Events.emit('request_failed', stage: 'unknown', error: "#{e.class}: #{e.message}")
    { ok: false, error: e.message }
  end

  private

  # Build the connection config. The caller passes either a cert path explicitly
  # or { no_cert: true } to omit the client cert. We keep server hostname/SAN
  # checks at default (verify_hostname=true, SNI='api').
  def config_for(opts)
    base = {
      url:     "#{@api_url}/whoami",
      sni:     'api-gateway',      # SAN do cert do nginx api-gateway
      ca_file: CA_FILE
    }

    if opts[:no_cert]
      base.merge(client_cert: nil, client_key: nil)
    else
      cert_path = opts[:cert_path] or raise ArgumentError, 'missing cert_path'
      # Allowlist: /run (step-ca), /certs (fixtures) ou /data (onboarding).
      ok = [RUN_DIR, CERT_DIR, DATA_DIR].any? { |d| cert_path.start_with?(d + '/') }
      raise ArgumentError, "cert_path must be under #{RUN_DIR}, #{CERT_DIR} or #{DATA_DIR}" unless ok
      key_path = cert_path.sub(/\.crt$/, '.key')
      base.merge(client_cert: cert_path, client_key: key_path)
    end
  end
end
