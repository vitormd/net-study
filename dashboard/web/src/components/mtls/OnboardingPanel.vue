<script setup>
import { ref, onMounted } from 'vue'
import { useIdentity } from '../../composables/useIdentity'
import CopyButton from '../CopyButton.vue'

const { active, refreshStatus, generate, sign, install, reset } = useIdentity()

const cn = ref('client-02')
const csrOut = ref('')
const csrIn = ref('')
const certOut = ref('')
const certIn = ref('')
const installResult = ref({ cls: '', text: '' })
const busy = ref({ gen: false, sign: false, install: false })

onMounted(refreshStatus)

async function onGenerate() {
  busy.value.gen = true
  try {
    const { ok, text } = await generate(cn.value.trim() || 'client-02')
    csrOut.value = ok ? text : `# erro: ${text}`
  } finally {
    busy.value.gen = false
  }
}

async function onSign() {
  const csr = csrIn.value.trim()
  if (!csr) return
  busy.value.sign = true
  try {
    const { ok, text } = await sign(csr)
    certOut.value = ok ? text : `# erro: ${text}`
  } finally {
    busy.value.sign = false
  }
}

async function onInstall() {
  const cert = certIn.value.trim()
  if (!cert) return
  busy.value.install = true
  installResult.value = { cls: '', text: '' }
  try {
    const data = await install(cert)
    installResult.value = data.ok
      ? { cls: 'ok', text: `instalado ✓  CN=${data.cn}  serial=${data.serial}  válido até ${data.not_after}` }
      : { cls: 'err', text: `falhou: ${data.reason}` }
  } finally {
    busy.value.install = false
  }
}

async function onReset() {
  await reset()
  csrOut.value = ''
  csrIn.value = ''
  certOut.value = ''
  certIn.value = ''
  installResult.value = { cls: '', text: '' }
}
</script>

<template>
  <section class="onboarding">
    <h2>Onboarding mTLS <span class="muted">— gere uma identidade e use no próximo request</span></h2>
    <div class="onboarding-status">
      Identidade ativa no client: <code>{{ active }}</code>
    </div>

    <div class="cards">
      <!-- Card 1 -->
      <div class="card">
        <h3><span class="step">1</span> Gerar par no client</h3>
        <p class="muted">A chave privada é criada dentro do container do <code>client</code> e nunca sai de lá.</p>
        <label>CN do certificado (identidade):</label>
        <input v-model="cn" type="text" placeholder="ex.: client-02, acme-prod">
        <button :disabled="busy.gen" @click="onGenerate">Gerar par de chaves</button>
        <label>CSR (chave pública + identidade, vai pra CA):</label>
        <textarea v-model="csrOut" readonly placeholder="-----BEGIN CERTIFICATE REQUEST-----"></textarea>
        <CopyButton :text="csrOut" label="Copiar CSR" />
      </div>

      <!-- Card 2 -->
      <div class="card">
        <h3><span class="step">2</span> Assinar CSR (CA)</h3>
        <p class="muted">Cole o CSR aqui. O dashboard repassa pro <code>step-ca</code> e devolve o cert assinado.</p>
        <label>CSR recebido:</label>
        <textarea v-model="csrIn" placeholder="cole o CSR do passo 1"></textarea>
        <button :disabled="busy.sign" @click="onSign">Assinar com a CA</button>
        <label>Certificado emitido:</label>
        <textarea v-model="certOut" readonly placeholder="-----BEGIN CERTIFICATE-----"></textarea>
        <CopyButton :text="certOut" label="Copiar cert" />
      </div>

      <!-- Card 3 -->
      <div class="card">
        <h3><span class="step">3</span> Instalar no client</h3>
        <p class="muted">Cole o cert. O client checa que a chave pública bate com a privada que ele guardou.</p>
        <label>Certificado a instalar:</label>
        <textarea v-model="certIn" placeholder="cole o cert do passo 2"></textarea>
        <button :disabled="busy.install" @click="onInstall">Instalar no client</button>
        <div class="result" :class="installResult.cls">{{ installResult.text }}</div>
        <button class="reset" @click="onReset">Reverter para client-01</button>
      </div>
    </div>
  </section>
</template>
