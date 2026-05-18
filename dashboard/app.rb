# Dashboard: event collector + SSE broadcaster + static SPA host.
#
# Routes:
#   POST /events           — services post JSON events here
#   GET  /stream           — SSE endpoint the browser subscribes to
#   POST /trigger/:name    — proxy to client's POST /run/:name
#   GET  /certs            — JSON inventory of the certs in /certs
#   GET  /                 — index.html + assets from public/

require 'sinatra/base'
require 'json'
require 'openssl'
require 'net/http'
require 'uri'
require 'shellwords'
require 'socket'
require_relative 'probe'

class Dashboard < Sinatra::Base
  set :environment, :production
  set :public_folder, File.expand_path('public', __dir__)
  disable :logging

  # ------------------------------------------------------------------------
  # In-memory pub/sub for SSE subscribers.
  # Each connection registers a Queue; broadcast pushes onto every queue.
  # ------------------------------------------------------------------------
  # SSE pub/sub: each subscriber owns a Queue; broadcast pushes to all queues.
  # The Rack body's `each` blocks on Queue#pop and yields chunks to Puma.
  @@mutex = Mutex.new
  @@subscribers = []

  def self.broadcast(event_json)
    @@mutex.synchronize do
      @@subscribers.each { |q| q.push("data: #{event_json}\n\n") rescue nil }
    end
  end

  def self.subscribe
    q = Queue.new
    @@mutex.synchronize { @@subscribers << q }
    q
  end

  def self.unsubscribe(q)
    @@mutex.synchronize { @@subscribers.delete(q) }
  end

  # Streaming body for Rack. Iterates on the queue until the client disconnects.
  #
  # Cada conexão SSE prende uma thread do Puma enquanto está aberta. Sem um
  # keepalive, uma conexão morta (aba fechada) nunca tenta escrever, então o
  # disconnect não é detectado e a thread vaza — esgotando o pool. Por isso o
  # `pop(timeout:)`: a cada 20s sem evento, escrevemos um comentário `: ping`,
  # cuja falha de escrita derruba o loop e libera a thread.
  CLOSE = :__sse_close__

  class SSEBody
    def initialize(queue)
      @queue = queue
    end

    def each
      yield ": connected\n\n"
      loop do
        msg = @queue.pop(timeout: 20)
        break if msg == CLOSE
        yield(msg.nil? ? ": ping\n\n" : msg)
      end
    rescue StandardError
      # client disconnect — fall through to ensure block
    ensure
      Dashboard.unsubscribe(@queue)
    end

    def close; @queue.push(CLOSE); end
  end

  # ------------------------------------------------------------------------
  # Events ingest
  # ------------------------------------------------------------------------
  post '/events' do
    body = request.body.read
    # Light validation: must parse as JSON.
    begin
      JSON.parse(body)
    rescue JSON::ParserError
      halt 400, 'invalid json'
    end
    Dashboard.broadcast(body)
    status 204
  end

  # Ingest específico do sniffer — repassa o payload inteiro pro SSE.
  # Aceita formato antigo (line only) e novo (src/dst/tls/...).
  post '/packet' do
    body = JSON.parse(request.body.read) rescue {}
    body['type']   ||= 'packet'
    body['source'] ||= 'sniffer'
    body['ts']     ||= Time.now.utc.iso8601(3)
    Dashboard.broadcast(body.to_json)
    status 204
  end

  # ------------------------------------------------------------------------
  # Server-Sent Events stream
  # ------------------------------------------------------------------------
  get '/stream' do
    q = Dashboard.subscribe
    [200,
     { 'content-type' => 'text/event-stream',
       'cache-control' => 'no-cache',
       'x-accel-buffering' => 'no' },
     SSEBody.new(q)]
  end

  # ------------------------------------------------------------------------
  # Trigger scenarios on the client
  # ------------------------------------------------------------------------
  # Body JSON repassado ao client: { cert_path: "..." } | { no_cert: true }
  post '/trigger' do
    proxy_to_client('POST', '/run', request.body.read)
  end

  get '/client-certs' do
    proxy_to_client('GET', '/certs/available')
  end

  # ------------------------------------------------------------------------
  # CA — assina CSR. Em produção isso seria um serviço com policy/auth próprio;
  # aqui ele mora junto do dashboard só pra simplificar o lab. A chave da CA
  # é lida do mesmo /certs montado read-only.
  # ------------------------------------------------------------------------
  # POST /ca/sign body=CSR PEM. Antes era assinatura inline em Ruby; agora é
  # proxy pro step-ca via CLI. Mostra como um portal/operador real funciona:
  # recebe CSR, pede token ao step-ca via JWK auth, submete CSR + token, devolve cert.
  post '/ca/sign' do
    csr_pem = request.body.read
    begin
      csr = OpenSSL::X509::Request.new(csr_pem)
    rescue OpenSSL::X509::RequestError => e
      halt 400, { error: "invalid CSR: #{e.message}" }.to_json
    end

    unless csr.verify(csr.public_key)
      halt 400, { error: 'CSR signature does not verify (proof-of-possession failed)' }.to_json
    end

    cn = csr.subject.to_a.find { |k, _, _| k == 'CN' }&.dig(1)
    fp = OpenSSL::Digest::SHA256.new(csr.public_key.to_der).hexdigest[0, 32]
    Dashboard.broadcast({ ts: Time.now.utc.iso8601(3), source: 'dashboard',
                          type: 'csr_received', cn: cn, public_key_fp: fp,
                          via: 'step-ca' }.to_json)

    # Escreve CSR num temp file, gera token via JWK provisioner, chama step ca sign.
    csr_file  = "/tmp/csr-#{Process.pid}-#{rand(1<<32)}.pem"
    cert_file = "#{csr_file}.crt"
    File.write(csr_file, csr_pem)

    ca_url = 'https://step-ca:9000'
    root   = '/step-data/certs/root_ca.crt'
    pwd    = '/tmp/ca-pwd'
    File.write(pwd, ENV.fetch('CA_PASSWORD', 'changeme-lab'))

    token_cmd = ['step', 'ca', 'token', cn,
                 '--provisioner', 'admin',
                 '--password-file', pwd,
                 '--ca-url', ca_url, '--root', root]
    # stderr tem a linha "Provisioner: admin (JWK)" — descartamos.
    token = `#{token_cmd.shelljoin} 2>/dev/null`.strip
    if $?.exitstatus != 0 || token.empty?
      halt 500, { error: "token request failed (exit=#{$?.exitstatus})" }.to_json
    end

    sign_cmd = ['step', 'ca', 'sign', csr_file, cert_file,
                '--token', token,
                '--not-after', '24h',   # cap do provisioner JWK do step-ca — coerente com "TTL curto em prod"
                '--ca-url', ca_url, '--root', root,
                '--force']
    out = `#{sign_cmd.shelljoin} 2>&1`
    if $?.exitstatus != 0
      halt 500, { error: "sign failed: #{out}" }.to_json
    end

    pem = File.read(cert_file)
    issued = OpenSSL::X509::Certificate.new(pem)

    Dashboard.broadcast({ ts: Time.now.utc.iso8601(3), source: 'dashboard',
                          type: 'csr_signed', cn: cn, serial: issued.serial.to_s,
                          not_after: issued.not_after.utc.iso8601, via: 'step-ca' }.to_json)

    content_type 'application/x-pem-file'
    pem
  ensure
    File.delete(csr_file)  if csr_file  && File.exist?(csr_file)
    File.delete(cert_file) if cert_file && File.exist?(cert_file)
  end

  # ------------------------------------------------------------------------
  # Identity proxy — repassa pro client, que é quem tem a chave privada.
  # ------------------------------------------------------------------------
  post '/identity/new' do
    proxy_to_client('POST', '/identity/new', request.body.read)
  end

  post '/identity/install' do
    proxy_to_client('POST', '/identity/install', request.body.read)
  end

  post '/identity/reset' do
    proxy_to_client('POST', '/identity/reset', '')
  end

  get '/identity/status' do
    proxy_to_client('GET', '/identity/status')
  end

  helpers do
    def proxy_to_client(method, path, body = nil)
      client = ENV.fetch('CLIENT_URL', 'http://[fd00:dead:beef::21]:4000')
      uri = URI("#{client}#{path}")
      http = Net::HTTP.new(uri.host.to_s.delete('[]'), uri.port)
      http.open_timeout = 2
      http.read_timeout = 10
      headers = { 'content-type' => request.content_type || 'application/octet-stream' }
      req = (method == 'POST' ? Net::HTTP::Post : Net::HTTP::Get).new(uri.path, headers)
      req.body = body if body
      res = http.request(req)
      status res.code.to_i
      content_type res['content-type'] || 'application/json'
      res.body
    rescue StandardError => e
      status 502
      { error: e.message }.to_json
    end
  end

  # ------------------------------------------------------------------------
  # Cert inventory
  # ------------------------------------------------------------------------
  get '/certs' do
    content_type :json
    out = {}
    Dir.glob('/certs/*.crt').sort.each do |path|
      cert = OpenSSL::X509::Certificate.new(File.read(path))
      out[File.basename(path)] = {
        subject:    cert.subject.to_s,
        issuer:     cert.issuer.to_s,
        not_before: cert.not_before.utc.iso8601,
        not_after:  cert.not_after.utc.iso8601,
        serial:     cert.serial.to_s,
        sha256_fp:  OpenSSL::Digest::SHA256.new(cert.to_der).hexdigest.scan(/../).join(':'),
        san:        san_of(cert),
        eku:        eku_of(cert)
      }
    rescue StandardError => e
      out[File.basename(path)] = { error: e.message }
    end
    out.to_json
  end

  helpers do
    def san_of(cert)
      ext = cert.extensions.find { |e| e.oid == 'subjectAltName' }
      ext&.value
    end

    def eku_of(cert)
      ext = cert.extensions.find { |e| e.oid == 'extendedKeyUsage' }
      ext&.value
    end
  end

  # IPv6 lab: rota o probe pra ser executado a partir de um dos containers.
  # POST /probe-from/:node  body={"url":"..."}
  NODES = {
    'dashboard' => nil,  # roda localmente
    'client'    => ENV.fetch('CLIENT_URL', 'http://[fd00:dead:beef::21]:4000'),
    'api'       => 'http://[fd00:dead:beef::20]:4000'
  }.freeze

  post '/probe-from/:node' do
    node = params['node']
    halt 404, '{"error":"unknown node"}' unless NODES.key?(node)

    body = JSON.parse(request.body.read) rescue {}
    url = body['url']
    halt 400, '{"error":"missing url"}' unless url && !url.empty?

    content_type :json
    if node == 'dashboard'
      Probe.run(url).to_json
    else
      proxy_get(NODES[node], "/probe?url=#{URI.encode_www_form_component(url)}")
    end
  end

  # Allowlist da api — exposta via porta de controle (4000, plain HTTP).
  get '/api/authorization' do
    proxy_get('http://[fd00:dead:beef::20]:4000', '/authorization')
  end

  put '/api/authorization' do
    proxy_to('PUT', 'http://[fd00:dead:beef::20]:4000', '/authorization', request.body.read)
  end

  get '/topology' do
    content_type :json
    {
      'dashboard' => { ipv6: 'fd00:dead:beef::30', interfaces: safe_local(Probe.interfaces) },
      'client'    => { ipv6: 'fd00:dead:beef::21', interfaces: safe_remote('client') },
      'api'       => { ipv6: 'fd00:dead:beef::20', interfaces: safe_remote('api') },
      # api-gateway (nginx) e step-ca não rodam nosso código Ruby — sem /interfaces.
      # Resolvemos via Docker DNS daqui (dashboard está na lab6).
      'api-gateway' => { ipv6: 'fd00:dead:beef::25', interfaces: resolve_via_dns('api-gateway') },
      'step-ca'     => { ipv6: 'fd00:dead:beef::10', interfaces: resolve_via_dns('step-ca') }
    }.to_json
  end

  helpers do
    def safe_local(ifaces)
      ifaces
    rescue StandardError => e
      [{ error: e.message }]
    end

    def safe_remote(node)
      url = NODES[node]
      uri = URI("#{url}/interfaces")
      http = Net::HTTP.new(uri.host.to_s.delete('[]'), uri.port)
      http.open_timeout = 1; http.read_timeout = 2
      JSON.parse(http.get(uri.path).body)
    rescue StandardError => e
      [{ error: e.message }]
    end

    def resolve_via_dns(name)
      Addrinfo.getaddrinfo(name, nil, nil, :STREAM).uniq { |a| a.ip_address }.map do |a|
        family = a.ipv6? ? 'inet6' : 'inet'
        scope  =
          if a.ipv6_linklocal?     then 'link-local'
          elsif a.ipv6_unique_local? then 'ula'
          elsif a.ipv6?            then 'global'
          else                          'ipv4'
          end
        { addr: a.ip_address, family: family, scope: scope }
      end
    rescue StandardError => e
      [{ error: e.message }]
    end

    def proxy_get(base, path)
      proxy_to('GET', base, path, nil)
    end

    def proxy_to(method, base, path, body)
      uri = URI("#{base}#{path}")
      http = Net::HTTP.new(uri.host.to_s.delete('[]'), uri.port)
      http.open_timeout = 2; http.read_timeout = 10
      klass = { 'GET' => Net::HTTP::Get, 'PUT' => Net::HTTP::Put, 'POST' => Net::HTTP::Post }[method]
      req = klass.new(uri.request_uri, 'content-type' => request.content_type || 'application/json')
      req.body = body if body
      res = http.request(req)
      status res.code.to_i
      content_type res['content-type'] || 'application/json'
      res.body
    rescue StandardError => e
      status 502
      { error: e.message }.to_json
    end
  end

  get '/' do
    send_file File.join(settings.public_folder, 'index.html')
  end

  # SPA fallback (Vue Router em history mode). Definido por último: as rotas
  # de API acima e os arquivos estáticos (/assets/*) já foram resolvidos —
  # só /mtls, /ipv6 e afins caem aqui e recebem o index.html.
  get '/*' do
    send_file File.join(settings.public_folder, 'index.html')
  end
end
