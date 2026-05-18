<script setup>
import { ref, watch } from 'vue'
import { useProbe } from '../../composables/useProbe'
import ProbeResultCard from './ProbeResultCard.vue'

const { origin, run } = useProbe()

const PRESETS = [
  { value: 'https://ifconfig.co/json', label: 'ifconfig.co (v4 + v6, JSON)' },
  { value: 'https://api64.ipify.org?format=json', label: 'api64.ipify.org (v4 ou v6)' },
  { value: 'https://v6.ident.me/', label: 'v6.ident.me (somente IPv6 — só tem AAAA)' },
  { value: '', label: '(personalizado)' }
]

const preset = ref(PRESETS[0].value)
const url = ref(PRESETS[0].value)
const busy = ref(false)
const result = ref(null) // { error } | { host, dns, v4, v6, elapsed_ms }

// Preset preenche o campo de URL (exceto "personalizado").
watch(preset, (p) => { if (p) url.value = p })

async function onRun() {
  const target = url.value.trim()
  if (!target) return
  busy.value = true
  result.value = { pending: true }
  try {
    result.value = await run(target)
  } catch (e) {
    result.value = { error: e.message }
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section class="ipv6-probe">
    <h3>Probe externo <span class="muted">— resolve A + AAAA do alvo e tenta IPv4 e IPv6 em separado</span></h3>
    <div class="probe-form">
      <div class="probe-field">
        <label>Sai de</label>
        <span>{{ origin }}</span>
      </div>
      <div class="probe-field grow">
        <label>Alvo (URL)</label>
        <div class="probe-target">
          <select v-model="preset">
            <option v-for="p in PRESETS" :key="p.label" :value="p.value">{{ p.label }}</option>
          </select>
          <input v-model="url" type="text" placeholder="https://...">
        </div>
      </div>
      <button id="probe-run" :disabled="busy" @click="onRun">Testar</button>
    </div>

    <div id="probe-result">
      <template v-if="result?.pending">
        <div class="probe-meta">⏳ probing <code>{{ url }}</code> a partir de <code>{{ origin }}</code>…</div>
      </template>
      <template v-else-if="result?.error">
        <div class="probe-card err"><h4>erro</h4>{{ result.error }}</div>
      </template>
      <template v-else-if="result">
        <div class="probe-meta">
          <strong>{{ result.host }}</strong> · DNS A:
          <code>{{ (result.dns?.A || []).join(', ') || '—' }}</code> · AAAA:
          <code>{{ (result.dns?.AAAA || []).join(', ') || '—' }}</code> · {{ result.elapsed_ms }}ms
        </div>
        <div class="probe-pair">
          <ProbeResultCard family="IPv4" :info="result.v4 || { ok: false, error: 'sem dado' }" />
          <ProbeResultCard family="IPv6" :info="result.v6 || { ok: false, error: 'sem dado' }" />
        </div>
      </template>
    </div>
  </section>
</template>
