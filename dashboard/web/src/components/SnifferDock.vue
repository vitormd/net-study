<script setup>
import { usePackets } from '../composables/usePackets'
import { classifyPacket, packetLabel, packetMeta, shortIp } from '../lib/packet'
import { logTime } from '../lib/eventLog'
import SnifferLegend from './SnifferLegend.vue'

const { packets, capturing, clear } = usePackets()
</script>

<template>
  <aside class="sniffer-dock">
    <h3>
      <span><code>tshark</code> live <span class="muted">· TLS dissector · gateway/api/client/step-ca</span></span>
      <span class="sniffer-controls">
        <SnifferLegend />
        <label><input type="checkbox" v-model="capturing"> capturar</label>
        <button @click="clear">limpar</button>
      </span>
    </h3>
    <ol id="packets">
      <li v-for="(p, i) in packets" :key="p.ts + '-' + i" :class="classifyPacket(p)">
        <span class="ts">{{ logTime(p.ts) }}</span>
        <span class="flow">{{ shortIp(p.src) }}:{{ p.sport }} → {{ shortIp(p.dst) }}:{{ p.dport }}</span>
        <span class="label">{{ packetLabel(p) }}</span>
        <span class="meta">{{ packetMeta(p) }}</span>
      </li>
    </ol>
  </aside>
</template>
