// Dispara uma requisição mTLS no client (POST /trigger).
// body: { no_cert: true } ou { cert_path: '...' }

export function useTriggers() {
  async function fire(body) {
    await fetch('/trigger', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body)
    })
  }
  return { fire }
}
