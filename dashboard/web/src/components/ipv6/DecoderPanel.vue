<script setup>
import { ref } from 'vue'
import { decodeIPv6 } from '../../lib/ipv6'

const PRESETS = [
  { addr: 'fd00:dead:beef::20', label: 'fd00:dead:beef::20 (api)' },
  { addr: '2001:db8::1', label: '2001:db8::1 (documentação)' },
  { addr: 'fe80::1', label: 'fe80::1 (link-local)' },
  { addr: '2606:4700:3030::ac43:a86a', label: '2606:4700:… (Cloudflare)' },
  { addr: '::1', label: '::1 (loopback)' }
]

const input = ref('fd00:dead:beef::20')
const result = ref(decodeIPv6('fd00:dead:beef::20'))

function decode(addr) {
  if (addr !== undefined) input.value = addr
  const v = input.value.trim()
  if (v) result.value = decodeIPv6(v)
}
</script>

<template>
  <section class="ipv6-decoder">
    <h3>Anatomia de um endereço IPv6
      <span class="muted">— quebra um endereço em prefixo, sub-rede e ID de interface</span>
    </h3>
    <div class="decoder-input">
      <input v-model="input" type="text"
             placeholder="ex.: fd00:dead:beef::20 ou 2606:4700:3030::ac43:a86a"
             @keydown.enter="decode()">
      <button @click="decode()">Decompor</button>
    </div>

    <div id="decoder-output">
      <template v-if="result && !result.ok">
        <div class="probe-card err"><h4>inválido</h4>não consegui parsear "{{ result.input }}"</div>
      </template>
      <template v-else-if="result">
        <div class="decoder-block">
          <div><span class="kind" :class="result.kind">{{ result.kind }}</span><code>{{ result.expanded }}</code></div>
          <div class="desc">{{ result.description }}</div>
        </div>
        <div class="bit-bar">
          <div v-for="(s, i) in result.segments" :key="i" class="seg" :class="s.cls">{{ s.hex }}</div>
        </div>
        <div class="decoder-legend">
          <span><span class="swatch" style="background:#58a6ff"></span>prefixo</span>
          <span><span class="swatch" style="background:#d2a8ff"></span>global routing</span>
          <span><span class="swatch" style="background:#f0b85a"></span>subnet</span>
          <span><span class="swatch" style="background:#56d364"></span>interface ID</span>
        </div>
        <div class="decoder-fields">
          <template v-for="(f, i) in result.fields" :key="i">
            <div class="k">{{ f.name }}</div>
            <div class="v">
              <span class="bit-bar">
                <span class="seg" :class="f.cls" style="padding:0 8px">{{ f.slice }}</span>
              </span>
              <div class="decoder-field-hint">{{ f.hint }}</div>
            </div>
          </template>
        </div>
      </template>
    </div>

    <div class="decoder-presets">
      Exemplos:
      <button v-for="p in PRESETS" :key="p.addr" class="preset" @click="decode(p.addr)">{{ p.label }}</button>
    </div>
  </section>
</template>
