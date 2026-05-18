# Sniffer com dissector TLS via tshark. Cada linha do tshark vira um evento JSON
# rico (content_type, handshake_type, SNI, ciphers) que o dashboard renderiza
# colorido — em vez do "Flags [S] length 0" cru do tcpdump.

require 'net/http'
require 'uri'
require 'json'
require 'time'

DASHBOARD = ENV.fetch('DASHBOARD_URL', 'http://[fd00:dead:beef::30]')

# Capturar na bridge da rede lab6 (em vez de "any") evita duplicação: tshark
# em "any" vê o pacote em CADA veth das duas pontas.
def discover_bridge
  return ENV['IFACE'] if ENV['IFACE'] && ENV['IFACE'] != 'auto'
  current = nil
  `ip -6 addr show 2>/dev/null`.each_line do |line|
    if (m = line.match(/^\d+:\s+(\S+):/))
      current = m[1]
    elsif current && line.include?('fd00:dead:beef:')
      return current
    end
  end
  'any'
end

def discover_node_ips(base_url)
  20.times do
    begin
      uri = URI("#{base_url}/interfaces")
      http = Net::HTTP.new(uri.host.to_s.delete('[]'), uri.port)
      http.open_timeout = 1; http.read_timeout = 1
      ips = JSON.parse(http.get(uri.path).body).map { |i| i['addr'] }
      return ips.reject { |ip| ip.include?('%') }
    rescue StandardError
      sleep 1
    end
  end
  []
end

def discover_via_topology(dashboard_url, node)
  20.times do
    begin
      uri = URI("#{dashboard_url}/topology")
      http = Net::HTTP.new(uri.host.to_s.delete('[]'), uri.port)
      http.open_timeout = 1; http.read_timeout = 1
      data = JSON.parse(http.get(uri.path).body)
      ips = (data.dig(node, 'interfaces') || []).map { |i| i['addr'] }.compact
      ips << data.dig(node, 'ipv6')
      return ips.compact.uniq.reject { |ip| ip.include?('%') }
    rescue StandardError
      sleep 1
    end
  end
  []
end

api_ips     = discover_node_ips('http://[fd00:dead:beef::20]:4000')
client_ips  = discover_node_ips('http://[fd00:dead:beef::21]:4000')
step_ca_ips     = discover_via_topology(DASHBOARD, 'step-ca')
api_gateway_ips = discover_via_topology(DASHBOARD, 'api-gateway')

warn "api IPs:         #{api_ips.inspect}"
warn "client IPs:      #{client_ips.inspect}"
warn "step-ca IPs:     #{step_ca_ips.inspect}"
warn "api-gateway IPs: #{api_gateway_ips.inspect}"

hosts = (api_ips + client_ips + step_ca_ips + api_gateway_ips).map { |ip| "host #{ip}" }.join(' or ')
FILTER = ENV['FILTER'] || "tcp and (port 8443 or port 8000 or port 443 or port 9000) and (#{hosts})"
IFACE  = discover_bridge

# --- TLS lookup tables ------------------------------------------------------

CONTENT_TYPE = {
  '20' => 'ChangeCipherSpec', '21' => 'Alert',
  '22' => 'Handshake',        '23' => 'ApplicationData',
  '24' => 'Heartbeat'
}.freeze

HANDSHAKE_TYPE = {
  '1'  => 'ClientHello',    '2'  => 'ServerHello',
  '4'  => 'NewSessionTicket','5'  => 'EndOfEarlyData',
  '8'  => 'EncryptedExtensions',
  '11' => 'Certificate',    '12' => 'ServerKeyExchange',
  '13' => 'CertificateRequest','14' => 'ServerHelloDone',
  '15' => 'CertificateVerify','16' => 'ClientKeyExchange',
  '20' => 'Finished',       '24' => 'KeyUpdate'
}.freeze

TLS_VERSION = {
  '0x0303' => 'TLS 1.2', '0x0304' => 'TLS 1.3',
  '0x0301' => 'TLS 1.0', '0x0302' => 'TLS 1.1'
}.freeze

# --- HTTP client (keep-alive p/ não criar conexão por linha) ---------------

uri = URI("#{DASHBOARD}/packet")
http = Net::HTTP.new(uri.host.to_s.delete('[]'), uri.port)
http.open_timeout = 2; http.read_timeout = 2
http.keep_alive_timeout = 30

30.times do
  begin
    http.start
    break
  rescue StandardError => e
    warn "waiting for dashboard at #{DASHBOARD}: #{e.message}"
    sleep 1
  end
end

def post_event(http, payload)
  req = Net::HTTP::Post.new('/packet', 'content-type' => 'application/json')
  req.body = payload.to_json
  http.request(req)
rescue StandardError
  begin
    http.finish rescue nil
    http.start
    http.request(req)
  rescue StandardError
  end
end

# --- tshark spawn -----------------------------------------------------------

SEP = "\x01"   # caractere pouco provável de aparecer em IPs/portas/strings
FIELDS = %w[
  frame.time_epoch
  ipv6.src ipv6.dst ip.src ip.dst
  tcp.srcport tcp.dstport tcp.flags tcp.len
  tls.record.content_type
  tls.handshake.type
  tls.handshake.version
  tls.handshake.extensions_server_name
  tls.handshake.ciphersuite
]

cmd = ['tshark', '-i', IFACE, '-l', '-n', '-Q',
       '-f', FILTER,
       '-T', 'fields',
       '-E', "separator=#{SEP}",
       '-E', 'quote=n',
       '-E', 'header=n',
       *FIELDS.flat_map { |f| ['-e', f] }]

warn "sniffer started: iface=#{IFACE} filter=#{FILTER.inspect}"

IO.popen(cmd, err: %i[child out]) do |io|
  io.each_line do |line|
    line.chomp!
    next if line.empty?
    parts = line.split(SEP, FIELDS.length)
    next if parts.length < FIELDS.length

    time, v6s, v6d, v4s, v4d, sport, dport, flags, len,
      ct, ht, ver, sni, ciphers = parts

    src = v6s.empty? ? v4s : v6s
    dst = v6d.empty? ? v4d : v6d
    next if src.empty? || dst.empty?

    ts = Time.at(time.to_f).utc.iso8601(3) rescue Time.now.utc.iso8601(3)

    payload = {
      type: 'packet', source: 'sniffer', ts: ts,
      src: src, dst: dst,
      sport: sport.to_i, dport: dport.to_i,
      tcp_flags: flags, length: len.to_i
    }

    # Pode haver múltiplos records dentro de um pacote — tshark separa por ",".
    ct_arr = ct.split(',').reject(&:empty?)
    ht_arr = ht.split(',').reject(&:empty?)

    unless ct_arr.empty?
      payload[:tls] = {
        records:  ct_arr.map { |c| CONTENT_TYPE[c] || "type-#{c}" },
        handshakes: ht_arr.map { |h| HANDSHAKE_TYPE[h] || "hs-#{h}" },
        version:  TLS_VERSION[ver] || ver,
        sni:      sni.empty? ? nil : sni,
        ciphers:  ciphers.split(',').reject(&:empty?)
      }
    end

    post_event(http, payload)
  end
end
