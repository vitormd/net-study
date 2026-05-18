import { reactive } from 'vue'
import { useSSE } from './useSSE'

// Estado da animação do diagrama mTLS (client → api). Traduz eventos SSE em
// posição do pacote + classes dos nós.

const CLIENT_X = 200
const API_X = 500

const state = reactive({
  packetX: CLIENT_X,
  packetClass: 'hidden',   // hidden | '' | warn | ok | err
  clientClasses: [],       // subset de: active, ok, err
  apiClasses: [],
  stage: ''
})

let wired = false

function shortErr(msg) {
  if (!msg) return ''
  return msg.length > 60 ? msg.slice(0, 60) + '…' : msg
}

function reset() {
  state.packetX = CLIENT_X
  state.packetClass = 'hidden'
  state.clientClasses = []
  state.apiClasses = []
  state.stage = ''
}

// flash = adiciona uma classe temporária por 800ms (sem mexer em 'err' fixo).
function flash(which, cls) {
  const key = which === 'client' ? 'clientClasses' : 'apiClasses'
  if (!state[key].includes(cls)) state[key] = [...state[key], cls]
  setTimeout(() => {
    state[key] = state[key].filter((c) => c !== cls)
  }, 800)
}

function addClass(which, cls) {
  const key = which === 'client' ? 'clientClasses' : 'apiClasses'
  if (!state[key].includes(cls)) state[key] = [...state[key], cls]
}

function animate(ev) {
  switch (ev.type) {
    case 'request_started':
      reset()
      state.packetClass = ''
      state.stage = ev.mode === 'with-cert'
        ? `→ com cert ${ev.cert_path?.split('/').pop()}`
        : '→ sem cert'
      addClass('client', 'active')
      break
    case 'tcp_connecting':
      state.stage = 'TCP SYN →'
      state.packetX = CLIENT_X + 40
      break
    case 'tcp_connected':
      state.stage = 'TCP estabelecido'
      state.packetX = CLIENT_X + 80
      flash('api', 'active')
      break
    case 'tls_handshake_starting':
      state.stage = 'TLS ClientHello →'
      state.packetX = CLIENT_X + 120
      state.packetClass = 'warn'
      break
    case 'tls_handshake_completed':
      state.stage = `TLS OK · ${ev.protocol} · ${ev.cipher || ''}`
      state.packetX = API_X
      state.packetClass = 'ok'
      flash('api', 'ok')
      break
    case 'tls_handshake_failed':
      state.stage = `TLS FALHOU: ${shortErr(ev.error)}`
      state.packetClass = 'err'
      addClass('api', 'err')
      addClass('client', 'err')
      break
    case 'request_received':
      flash('api', 'ok')
      break
    case 'http_response':
      state.stage = `HTTP ${ev.status}`
      state.packetX = CLIENT_X
      flash('client', 'ok')
      break
    case 'request_failed':
      state.packetClass = 'err'
      addClass('client', 'err')
      break
  }
}

export function useDiagram() {
  const { on } = useSSE()
  if (!wired) {
    wired = true
    on('*', (ev) => animate(ev))
  }
  return { state, reset }
}
