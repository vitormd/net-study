import { ref } from 'vue'
import { useSSE } from './useSSE'

// Certs de cliente disponíveis pro dropdown de request (GET /client-certs).
// Recarrega sozinho quando uma identidade é instalada/resetada via onboarding.

const certs = ref([])
let wired = false

async function load() {
  try {
    certs.value = await (await fetch('/client-certs')).json()
  } catch (e) {
    console.error('client-certs load failed', e)
  }
}

export function useClientCerts() {
  const { on } = useSSE()
  if (!wired) {
    wired = true
    on('identity_installed', load)
    on('identity_reset', load)
  }
  return { certs, load }
}
