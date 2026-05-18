# GET /probe?url=... — testa conectividade de saída de um container.
# Tenta v4 e v6 separadamente pra evidenciar o que está disponível neste host.

require 'net/http'
require 'uri'
require 'json'
require 'resolv'
require 'socket'
require 'openssl'

module Probe
  TIMEOUT = 8

  # Lista de interfaces locais (útil para o grafo do dashboard).
  def self.interfaces
    Socket.ip_address_list.filter_map do |a|
      next if a.ipv6_loopback? || a.ipv4_loopback?
      family = a.ipv6? ? 'inet6' : 'inet'
      scope =
        if a.ipv6_linklocal?     then 'link-local'
        elsif a.ipv6_unique_local? then 'ula'
        elsif a.ipv6?            then 'global'
        else                          'ipv4'
        end
      { addr: a.ip_address, family: family, scope: scope }
    end
  end

  def self.run(url)
    started = Time.now
    uri = URI(url)
    host = uri.host

    a    = safe_resolve(host, Resolv::DNS::Resource::IN::A) { |r| r.address.to_s }
    aaaa = safe_resolve(host, Resolv::DNS::Resource::IN::AAAA) { |r| r.address.to_s }

    {
      host: host,
      url: url,
      dns: { A: a, AAAA: aaaa },
      v4: a.empty?    ? { ok: false, error: 'no A record' }    : fetch(uri, a.first),
      v6: aaaa.empty? ? { ok: false, error: 'no AAAA record' } : fetch(uri, aaaa.first),
      elapsed_ms: ((Time.now - started) * 1000).to_i
    }
  rescue StandardError => e
    { url: url, error: "#{e.class}: #{e.message}" }
  end

  def self.safe_resolve(host, type)
    Resolv::DNS.new.getresources(host, type).map { |r| yield(r) }
  rescue StandardError
    []
  end

  def self.fetch(uri, ip)
    port = uri.port || (uri.scheme == 'https' ? 443 : 80)
    sock = Socket.tcp(ip, port, connect_timeout: TIMEOUT)
    io = uri.scheme == 'https' ? wrap_tls(sock, uri.host) : sock

    path = uri.path.empty? ? '/' : uri.path
    path += "?#{uri.query}" if uri.query
    io.write("GET #{path} HTTP/1.1\r\nHost: #{uri.host}\r\nUser-Agent: net-study/probe\r\nAccept: application/json,*/*\r\nConnection: close\r\n\r\n")

    raw = +''
    deadline = Time.now + TIMEOUT
    while (chunk = io.read_nonblock(4096, exception: false))
      break if chunk == :wait_readable && !IO.select([io], nil, nil, [deadline - Time.now, 0].max)
      raw << chunk if chunk.is_a?(String)
      break if chunk.nil?
    end
    io.close rescue nil

    head, _, body = raw.partition("\r\n\r\n")
    status = head.lines.first.to_s.split[1]&.to_i
    { ok: true, remote_ip: ip, status: status, body: body[0, 400] }
  rescue StandardError => e
    sock&.close rescue nil
    { ok: false, remote_ip: ip, error: "#{e.class}: #{e.message}" }
  end

  def self.wrap_tls(sock, hostname)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
    ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
    ssl.hostname = hostname
    ssl.sync_close = true
    ssl.connect
    ssl
  end
end
