import { ref } from 'vue'

// Allowlist de CNs da api (GET/PUT /api/authorization).

const cns = ref([])

export function useAllowlist() {
  async function load() {
    try {
      const d = await (await fetch('/api/authorization')).json()
      cns.value = d.allowed_cns || []
    } catch (e) {
      console.error('allowlist load failed', e)
    }
  }

  async function save(list) {
    const res = await fetch('/api/authorization', {
      method: 'PUT',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ allowed_cns: list })
    })
    const d = await res.json()
    cns.value = d.allowed_cns || []
  }

  return { cns, load, save }
}
