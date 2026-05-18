import { ref } from 'vue'
import { useSSE } from './useSSE'

// Onboarding mTLS: status da identidade ativa + ações de gerar CSR, assinar
// (proxy pro step-ca) e instalar/reverter.

const active = ref('…')
let wired = false

async function refreshStatus() {
  try {
    const d = await (await fetch('/identity/status')).json()
    active.value = d.active || 'desconhecida'
  } catch {
    active.value = 'erro'
  }
}

export function useIdentity() {
  const { on } = useSSE()
  if (!wired) {
    wired = true
    on('identity_installed', refreshStatus)
    on('identity_reset', refreshStatus)
    on('identity_csr_generated', refreshStatus)
  }

  // Gera keypair + CSR no client. Retorna { ok, text } (text = PEM ou erro).
  async function generate(cn) {
    const res = await fetch('/identity/new', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ cn })
    })
    return { ok: res.ok, text: await res.text() }
  }

  // Submete o CSR pra CA (dashboard → step-ca). Retorna { ok, text }.
  async function sign(csr) {
    const res = await fetch('/ca/sign', {
      method: 'POST',
      headers: { 'content-type': 'application/x-pem-file' },
      body: csr
    })
    return { ok: res.ok, text: await res.text() }
  }

  // Instala o cert assinado de volta no client. Retorna o JSON da resposta.
  async function install(cert) {
    const res = await fetch('/identity/install', {
      method: 'POST',
      headers: { 'content-type': 'application/x-pem-file' },
      body: cert
    })
    return await res.json()
  }

  async function reset() {
    await fetch('/identity/reset', { method: 'POST' })
  }

  return { active, refreshStatus, generate, sign, install, reset }
}
