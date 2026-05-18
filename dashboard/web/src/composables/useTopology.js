import { ref } from 'vue'

// Topologia da rede (GET /topology) — IPs de cada nó pra desenhar o grafo.

const topology = ref({})

export function useTopology() {
  async function load() {
    try {
      topology.value = await (await fetch('/topology')).json()
    } catch (e) {
      console.error('topology load failed', e)
    }
  }
  return { topology, load }
}
