<script setup>
defineProps({
  family: { type: String, required: true },
  info: { type: Object, required: true }
})
</script>

<template>
  <div class="probe-card" :class="info.ok ? 'ok' : 'err'">
    <h4>{{ family }}</h4>
    <div class="row"><span class="k">via</span><span class="v">{{ family }}</span></div>
    <div v-if="info.remote_ip" class="row">
      <span class="k">peer</span><span class="v">{{ info.remote_ip }}</span>
    </div>
    <div v-if="info.status" class="row">
      <span class="k">status</span><span class="v">{{ info.status }}</span>
    </div>
    <div v-if="info.error" class="row">
      <span class="k">erro</span><span class="v">{{ info.error }}</span>
    </div>
    <pre v-if="info.body">{{ info.body }}</pre>
  </div>
</template>
