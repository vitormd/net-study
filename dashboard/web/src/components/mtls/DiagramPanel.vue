<script setup>
import { useDiagram } from '../../composables/useDiagram'

const { state } = useDiagram()
</script>

<template>
  <section class="diagram">
    <svg id="net" viewBox="0 0 700 240" preserveAspectRatio="xMidYMid meet">
      <g>
        <rect x="40" y="60" width="160" height="120" rx="14" :class="['node', ...state.clientClasses]" />
        <text x="120" y="110" class="node-label">client</text>
        <text x="120" y="140" class="node-sub">Sinatra · Net::HTTP mTLS</text>
      </g>
      <g>
        <rect x="500" y="60" width="160" height="120" rx="14" :class="['node', ...state.apiClasses]" />
        <text x="580" y="110" class="node-label">api-gateway</text>
        <text x="580" y="140" class="node-sub">nginx · termina mTLS</text>
      </g>
      <line x1="200" y1="120" x2="500" y2="120" class="wire" />
      <text x="350" y="105" class="wire-label" text-anchor="middle">HTTPS mTLS</text>
      <text x="350" y="145" class="wire-stage" text-anchor="middle">{{ state.stage }}</text>
      <circle r="10" :cx="state.packetX" cy="120" :class="['packet', state.packetClass]" />
    </svg>
  </section>
</template>
