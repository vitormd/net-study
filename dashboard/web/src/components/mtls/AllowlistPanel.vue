<script setup>
import { ref, onMounted, watch } from 'vue'
import { useAllowlist } from '../../composables/useAllowlist'

const { cns, load, save } = useAllowlist()
const draft = ref('')

onMounted(load)

// Mantém o textarea sincronizado quando a allowlist é (re)carregada.
watch(cns, (list) => { draft.value = list.join('\n') }, { immediate: true })

function onSave() {
  const list = draft.value.split(/[\n,]/).map((s) => s.trim()).filter(Boolean)
  save(list)
}

function onClear() {
  draft.value = ''
  save([])
}
</script>

<template>
  <section class="allowlist">
    <h2>Autorização na api <span class="muted">— mTLS valida o cert; allowlist decide se o CN pode chamar</span></h2>
    <p class="muted">
      Edite a lista (um CN por linha) e salve. Um request com cert de fora da lista vai bater na api e
      levar 403 mesmo com handshake bem-sucedido — autenticação ≠ autorização.
    </p>
    <div class="allowlist-row">
      <textarea v-model="draft" placeholder="client-01&#10;client-02"></textarea>
      <div class="allowlist-side">
        <button @click="onSave">Salvar allowlist</button>
        <button class="reset" @click="onClear">Limpar (vira modo aberto)</button>
        <div id="allowlist-current" class="muted">
          <template v-if="cns.length">
            estado atual: <code v-for="(c, i) in cns" :key="c">{{ c }}{{ i < cns.length - 1 ? ', ' : '' }}</code>
          </template>
          <template v-else>
            estado atual: <code>(vazia — modo aberto, qualquer CN passa)</code>
          </template>
        </div>
      </div>
    </div>
  </section>
</template>
