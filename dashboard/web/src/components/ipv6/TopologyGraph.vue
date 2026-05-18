<script setup>
import { computed, onMounted } from 'vue'
import { useTopology } from '../../composables/useTopology'
import { useProbe } from '../../composables/useProbe'

const { topology, load } = useTopology()
const { origin } = useProbe()

onMounted(load)

// Layout estático em 4 colunas. Endereços vêm do /topology.
const COL = { 1: 110, 2: 340, 3: 570, 4: 800 }
const ROW = { top: 80, mid: 200, bot: 320 }

const NODES = [
  { id: 'step-ca',     col: 1, row: 'top', label: 'step-ca',     sub: 'PKI · :9000 · TTL 24h',  dashed: true },
  { id: 'sniffer',     col: 1, row: 'bot', label: 'sniffer',     sub: 'tshark · TLS dissector', dashed: true, addr: 'host netns · bridge' },
  { id: 'client',      col: 2, row: 'top', label: 'client',      sub: 'Sinatra' },
  { id: 'api-gateway', col: 2, row: 'mid', label: 'api-gateway', sub: 'nginx · termina mTLS' },
  { id: 'api',         col: 2, row: 'bot', label: 'api',         sub: 'Sinatra · XFCC' },
  { id: 'dashboard',   col: 3, row: 'mid', label: 'dashboard',   sub: 'Sinatra (SSE)' },
  { id: 'external',    col: 4, row: 'mid', label: 'internet',    sub: 'destino do probe', external: true, addr: 'host externo' }
]

const LINKS = [
  { from: 'client',      to: 'api-gateway', label: 'mTLS (8443)' },
  { from: 'api-gateway', to: 'api',         label: 'HTTP + XFCC (8000)' },
  { from: 'client',      to: 'dashboard',   label: 'events' },
  { from: 'api',         to: 'dashboard',   label: 'events' },
  { from: 'api-gateway', to: 'step-ca',     kind: 'pki',      label: 'cert + renew' },
  { from: 'api',         to: 'step-ca',     kind: 'pki',      label: 'cert + renew' },
  { from: 'client',      to: 'step-ca',     kind: 'pki',      label: 'cert + renew' },
  { from: 'dashboard',   to: 'step-ca',     kind: 'pki',      label: 'sign CSR' },
  { from: 'sniffer',     to: 'api-gateway', kind: 'sniffing', label: 'sniff' },
  { from: 'sniffer',     to: 'api',         kind: 'sniffing', label: 'sniff' },
  { from: 'sniffer',     to: 'client',      kind: 'sniffing', label: 'sniff' },
  { from: 'sniffer',     to: 'step-ca',     kind: 'sniffing', label: 'sniff' },
  { from: 'dashboard',   to: 'external',    kind: 'external', label: 'probe' }
]

const SELECTABLE = ['client', 'api', 'dashboard']

const nodes = computed(() => NODES.map((n) => ({
  ...n,
  x: COL[n.col],
  y: ROW[n.row],
  addr: n.addr || topology.value[n.id]?.ipv6 || '—',
  selectable: SELECTABLE.includes(n.id)
})))

const byId = computed(() => Object.fromEntries(nodes.value.map((n) => [n.id, n])))

const links = computed(() => LINKS.map((l) => {
  const a = byId.value[l.from]
  const b = byId.value[l.to]
  return { ...l, x1: a.x, y1: a.y, x2: b.x, y2: b.y, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2 - 6 }
}))

function nodeClass(n) {
  return {
    'node-box': true,
    external: n.external,
    passive: n.dashed,
    'non-selectable': !n.selectable,
    selected: n.selectable && origin.value === n.id
  }
}

function selectOrigin(n) {
  if (n.selectable) origin.value = n.id
}
</script>

<template>
  <section class="ipv6-graph">
    <svg id="ipv6-net" viewBox="0 0 900 420" preserveAspectRatio="xMidYMid meet">
      <line v-for="(l, i) in links" :key="'l' + i"
            :x1="l.x1" :y1="l.y1" :x2="l.x2" :y2="l.y2"
            :class="['link', l.kind]" />
      <text v-for="(l, i) in links" :key="'t' + i"
            :x="l.mx" :y="l.my" class="node-sub" text-anchor="middle">{{ l.label }}</text>

      <g v-for="n in nodes" :key="n.id">
        <rect :x="n.x - 90" :y="n.y - 35" width="180" height="70" rx="10"
              :class="nodeClass(n)" @click="selectOrigin(n)" />
        <text :x="n.x" :y="n.y - 12" class="node-title">{{ n.label }}</text>
        <text :x="n.x" :y="n.y + 6" class="node-addr">{{ n.addr }}</text>
        <text :x="n.x" :y="n.y + 22" class="node-sub">{{ n.sub }}</text>
      </g>
    </svg>
  </section>
</template>
