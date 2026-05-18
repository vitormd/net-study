<script setup>
import { useEventLog } from '../../composables/useEventLog'
import { LOG_CLASSES, summarize, logTime } from '../../lib/eventLog'

const { entries, clear } = useEventLog()
</script>

<template>
  <section class="bottom">
    <div class="log-panel">
      <h3>Log de eventos TLS <button @click="clear">limpar</button></h3>
      <ol id="log">
        <li v-for="(ev, i) in entries" :key="ev.ts + '-' + i" :class="LOG_CLASSES[ev.type]">
          <span class="ts">{{ logTime(ev.ts) }}</span>
          <span class="src" :class="ev.source">{{ ev.source }}</span>
          <span class="type">{{ ev.type }}{{ summarize(ev) }}</span>
          <details>
            <summary class="muted" style="grid-column:1/-1;cursor:pointer">detalhes</summary>
            <pre>{{ JSON.stringify(ev, null, 2) }}</pre>
          </details>
        </li>
      </ol>
    </div>
  </section>
</template>
