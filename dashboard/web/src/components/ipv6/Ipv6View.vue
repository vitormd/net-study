<script setup>
import TopologyGraph from './TopologyGraph.vue'
import ProbePanel from './ProbePanel.vue'
import DecoderPanel from './DecoderPanel.vue'
</script>

<template>
  <div class="tab-view">
    <section class="ipv6-intro">
      <h2>Topologia da rede <span class="muted">— rede Docker ULA fd00:dead:beef::/64</span></h2>
      <p class="muted">Clique num nó (client, api ou dashboard) pra escolher de onde sai o probe. O nó externo é o destino do teste de eco IP.</p>
    </section>
    <TopologyGraph />
    <ProbePanel />
    <DecoderPanel />
  </div>
</template>
