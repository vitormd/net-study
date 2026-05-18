<script setup>
import OnboardingPanel from './OnboardingPanel.vue'
import AllowlistPanel from './AllowlistPanel.vue'
import ActionsPanel from './ActionsPanel.vue'
import DiagramPanel from './DiagramPanel.vue'
import LogPanel from './LogPanel.vue'
</script>

<template>
  <div class="tab-view">
    <OnboardingPanel />
    <AllowlistPanel />
    <ActionsPanel />
    <DiagramPanel />
    <LogPanel />
  </div>
</template>
