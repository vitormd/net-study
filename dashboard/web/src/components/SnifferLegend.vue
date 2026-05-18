<script setup>
// Ícone "?" com popup da legenda de cores. Acessível por teclado via :focus-within.
const ITEMS = [
  { sw: 'hs-client', label: 'ClientHello' },
  { sw: 'hs-server', label: 'ServerHello / Finished / NewSessionTicket' },
  { sw: 'hs-cert', label: 'Certificate / CertificateVerify' },
  { sw: 'hs-ccs', label: 'ChangeCipherSpec' },
  { sw: 'hs-data', label: 'ApplicationData' },
  { sw: 'hs-alert', label: 'Alert' },
  { sw: 'tls-other', label: 'outro TLS' }
]
const TCP = [
  { sw: 'syn', label: 'SYN (handshake TCP)' },
  { sw: 'ack', label: 'ACK puro' },
  { sw: 'fin', label: 'FIN / RST (encerramento)' }
]
</script>

<template>
  <span class="legend" tabindex="0" aria-label="Legenda de cores">
    <span class="legend-icon">?</span>
    <span class="legend-popup">
      <strong>Legenda do sniffer</strong>
      <span v-for="it in ITEMS" :key="it.sw"><i class="sw" :class="it.sw"></i> {{ it.label }}</span>
      <hr>
      <span v-for="it in TCP" :key="it.sw"><i class="sw" :class="it.sw"></i> {{ it.label }}</span>
    </span>
  </span>
</template>
