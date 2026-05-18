// Classificação e resumo dos eventos TLS pro LogPanel — lógica pura.

export const LOG_CLASSES = {
  tls_handshake_completed: 'ok',
  http_response: 'ok',
  tls_handshake_failed: 'err',
  request_failed: 'err',
  request_started: 'scenario',
  identity_installed: 'ok',
  csr_signed: 'ok',
  identity_install_failed: 'err',
  authorization_denied: 'err',
  authorization_updated: 'scenario'
}

function shortErr(msg) {
  if (!msg) return ''
  return msg.length > 60 ? msg.slice(0, 60) + '…' : msg
}

export function summarize(ev) {
  switch (ev.type) {
    case 'request_started':
      return ev.mode === 'with-cert' ? ` — com cert ${ev.cert_path}` : ' — sem cert'
    case 'tcp_connecting': return ` ${ev.host}:${ev.port}`
    case 'tcp_connected': return ` peer=${ev.remote_ip}`
    case 'tls_handshake_starting': return ` sni=${ev.sni} client_cert=${ev.presenting_client_cert}`
    case 'tls_handshake_completed': return ` ${ev.protocol} ${ev.cipher || ''}`
    case 'tls_handshake_failed': return ` — ${shortErr(ev.error)}`
    case 'http_response': return ` ${ev.status}`
    case 'request_received': return ` ${ev.method} ${ev.path} from CN=${ev.peer_cn || '?'}`
    case 'request_completed': return ` ${ev.path} → ${ev.status}`
    case 'request_failed': return ` — ${shortErr(ev.error)}`
    case 'identity_csr_generated': return ` CN=${ev.cn} (${ev.key_bits} bits)`
    case 'csr_received': return ` CN=${ev.cn} fp=${ev.public_key_fp?.slice(0, 16) || ''}`
    case 'csr_signed': return ` CN=${ev.cn} serial=${ev.serial} válido até ${ev.not_after}`
    case 'identity_installed': return ` CN=${ev.cn} serial=${ev.serial}`
    case 'identity_install_failed': return ` — ${ev.reason}`
    case 'identity_reset': return ' — voltou para client-01'
    case 'authorization_denied': return ` — CN=${ev.cn} fora da allowlist (${(ev.allowlist || []).join(', ')})`
    case 'authorization_updated': return ` — nova allowlist: ${(ev.allowlist || []).join(', ') || '(vazia, modo aberto)'}`
    default: return ''
  }
}

export function logTime(ts) {
  try { return new Date(ts).toISOString().slice(11, 23) } catch { return '' }
}
