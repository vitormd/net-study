<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { useClientCerts } from '../../composables/useClientCerts'
import { useTriggers } from '../../composables/useTriggers'
import { useDiagram } from '../../composables/useDiagram'
import { useEventLog } from '../../composables/useEventLog'

const { certs, load } = useClientCerts()
const { fire } = useTriggers()
const { reset: resetDiagram } = useDiagram()
const { clear: clearLog } = useEventLog()

const selected = ref('')
const busy = ref(false)

onMounted(load)

const options = computed(() => certs.value.map((c) => {
  let label = `${c.name}  ·  CN=${c.cn}  ·  issuer=${c.issuer_cn}`
  if (c.expired) label += '  ⚠ expirado'
  if (c.source === 'onboarding') label += '  (recém-instalado)'
  return { value: c.cert_path, label }
}))

// Garante uma seleção válida sempre que a lista de certs muda.
watch(options, (opts) => {
  if (!opts.find((o) => o.value === selected.value)) {
    selected.value = opts[0]?.value || ''
  }
}, { immediate: true })

async function fireRequest(body) {
  busy.value = true
  resetDiagram()
  try {
    await fire(body)
  } finally {
    setTimeout(() => { busy.value = false }, 400)
  }
}

function onReset() {
  clearLog()
  resetDiagram()
}
</script>

<template>
  <section class="actions">
    <h2>Disparar uma requisição <span class="muted">(um clique = uma requisição mTLS pra api)</span></h2>
    <div class="trigger-row">
      <button class="trigger break" :disabled="busy" @click="fireRequest({ no_cert: true })">
        Request sem certificado
        <span class="desc">cliente não apresenta cert; servidor rejeita no handshake</span>
      </button>
      <div class="trigger-with">
        <button class="trigger ok" :disabled="busy || !selected"
                @click="fireRequest({ cert_path: selected })">
          Request c/ certificado
          <span class="desc">usa o cert selecionado abaixo</span>
        </button>
        <label for="cert-pick" class="muted">Certificado a apresentar:</label>
        <select id="cert-pick" v-model="selected">
          <option v-if="!options.length" disabled value="">(nenhum cert disponível)</option>
          <option v-for="o in options" :key="o.value" :value="o.value">{{ o.label }}</option>
        </select>
      </div>
    </div>
    <button class="reset" @click="onReset">Resetar diagrama e log</button>
  </section>
</template>
