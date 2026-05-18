import { ref } from 'vue'
import { useSSE } from './useSSE'

// Buffer dos pacotes capturados pelo sniffer (type=packet via SSE).

const MAX = 200
const packets = ref([])
const capturing = ref(true)
let wired = false

export function usePackets() {
  const { on } = useSSE()
  if (!wired) {
    wired = true
    on('packet', (ev) => {
      if (!capturing.value) return
      packets.value.unshift(ev)
      if (packets.value.length > MAX) packets.value.pop()
    })
  }

  function clear() { packets.value = [] }

  return { packets, capturing, clear }
}
