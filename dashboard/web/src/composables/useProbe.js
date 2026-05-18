import { ref } from 'vue'

// Probe externo. `origin` é compartilhado entre o grafo (clique no nó) e o
// painel de probe.

const origin = ref('dashboard')

export function useProbe() {
  async function run(url) {
    const res = await fetch(`/probe-from/${origin.value}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ url })
    })
    return await res.json()
  }
  return { origin, run }
}
