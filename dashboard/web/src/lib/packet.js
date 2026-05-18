// Classificação visual dos pacotes do sniffer — lógica pura.

const TLS_CLASS = {
  ClientHello: 'hs-client',
  ServerHello: 'hs-server',
  Certificate: 'hs-cert',
  CertificateRequest: 'hs-cert',
  CertificateVerify: 'hs-cert',
  Finished: 'hs-fin',
  EncryptedExtensions: 'hs-fin',
  NewSessionTicket: 'hs-fin',
  ChangeCipherSpec: 'hs-ccs',
  Alert: 'hs-alert',
  ApplicationData: 'hs-data',
  Heartbeat: 'hs-data'
}

export function classifyPacket(ev) {
  if (ev.tls?.handshakes?.length) return TLS_CLASS[ev.tls.handshakes[0]] || 'tls-other'
  if (ev.tls?.records?.length) return TLS_CLASS[ev.tls.records[0]] || 'tls-other'
  const f = parseInt(ev.tcp_flags || '0', 16)
  if (f & 0x02) return 'syn'
  if (f & 0x01) return 'fin'
  if (f & 0x04) return 'fin'
  if (ev.length > 0) return 'data'
  return 'ack'
}

export function packetLabel(ev) {
  if (ev.tls?.handshakes?.length) return ev.tls.handshakes.join(' + ')
  if (ev.tls?.records?.length) return ev.tls.records.join(' + ')
  const f = parseInt(ev.tcp_flags || '0', 16)
  if (f & 0x02) return f & 0x10 ? 'SYN-ACK' : 'SYN'
  if (f & 0x01) return 'FIN'
  if (f & 0x04) return 'RST'
  if (ev.length > 0) return `data ${ev.length}B`
  return 'ACK'
}

// Encurta ULA do lab pra economizar espaço no dock.
export function shortIp(ip) {
  if (!ip) return ''
  if (ip.startsWith('fd00:dead:beef::')) return `::${ip.slice(16)}`
  return ip
}

export function packetMeta(ev) {
  const extra = []
  if (ev.tls?.sni) extra.push(`sni=${ev.tls.sni}`)
  if (ev.tls?.version) extra.push(ev.tls.version)
  if (ev.length > 0 && !ev.tls?.handshakes?.length) extra.push(`${ev.length}B`)
  return extra.join(' · ')
}
