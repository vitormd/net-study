<script setup>
import { computed } from 'vue'
import { RouterLink, RouterView } from 'vue-router'
import { useSSE } from './composables/useSSE'
import SnifferDock from './components/SnifferDock.vue'

const { status } = useSSE()

const STATUS_TEXT = {
  connecting: 'conectando…',
  connected: 'conectado ao stream',
  error: 'reconectando…'
}
const statusText = computed(() => STATUS_TEXT[status.value] || '')
const statusClass = computed(() => ({
  connected: status.value === 'connected',
  error: status.value === 'error'
}))
</script>

<template>
  <header>
    <h1>net-study</h1>
    <nav class="tabs">
      <RouterLink to="/" class="tab">Home</RouterLink>
      <RouterLink to="/mtls" class="tab">mTLS</RouterLink>
      <RouterLink to="/ipv6" class="tab">IPv6</RouterLink>
    </nav>
    <div id="status" class="status" :class="statusClass">{{ statusText }}</div>
  </header>

  <div class="app-shell">
    <main>
      <RouterView />
    </main>
    <SnifferDock />
  </div>
</template>
