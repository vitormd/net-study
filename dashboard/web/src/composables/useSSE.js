import { ref } from 'vue'

// Conexão SSE única pra todo o app. Os composables que precisam reagir a
// eventos chamam `on(type, cb)`; `on('*', cb)` recebe todos.

const status = ref('connecting') // 'connecting' | 'connected' | 'error'
const listeners = new Map()      // type -> Set<callback>
let es = null

function dispatch(ev) {
  for (const cb of listeners.get(ev.type) || []) cb(ev)
  for (const cb of listeners.get('*') || []) cb(ev)
}

function connect() {
  if (es) return
  es = new EventSource('/stream')
  es.onopen = () => { status.value = 'connected' }
  es.onerror = () => { status.value = 'error' }
  es.onmessage = (m) => {
    let ev
    try { ev = JSON.parse(m.data) } catch { return }
    dispatch(ev)
  }
}

export function useSSE() {
  connect()

  function on(type, cb) {
    if (!listeners.has(type)) listeners.set(type, new Set())
    listeners.get(type).add(cb)
    return () => listeners.get(type)?.delete(cb)
  }

  return { status, on }
}
