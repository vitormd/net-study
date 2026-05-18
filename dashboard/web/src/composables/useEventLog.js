import { ref } from 'vue'
import { useSSE } from './useSSE'

// Buffer dos eventos TLS pro LogPanel. Pacotes do sniffer (type=packet) são
// filtrados — vão pro usePackets.

const MAX = 200
const entries = ref([])
let wired = false

export function useEventLog() {
  const { on } = useSSE()
  if (!wired) {
    wired = true
    on('*', (ev) => {
      if (ev.type === 'packet') return
      entries.value.unshift(ev)
      if (entries.value.length > MAX) entries.value.pop()
    })
  }

  function clear() { entries.value = [] }

  return { entries, clear }
}
