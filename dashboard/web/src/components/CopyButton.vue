<script setup>
import { ref } from 'vue'

const props = defineProps({
  text: { type: String, default: '' },
  label: { type: String, default: 'Copiar' }
})

const copied = ref(false)

async function copy() {
  if (!props.text) return
  await navigator.clipboard.writeText(props.text)
  copied.value = true
  setTimeout(() => { copied.value = false }, 1200)
}
</script>

<template>
  <button class="copy" @click="copy">{{ copied ? 'copiado ✓' : label }}</button>
</template>
