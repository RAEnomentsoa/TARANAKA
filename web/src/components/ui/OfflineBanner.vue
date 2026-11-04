<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import InlineAlert from './InlineAlert.vue'

/** Health centres often lose the network: say so instead of failing silently. */
const { t } = useI18n()
const online = ref(typeof navigator === 'undefined' ? true : navigator.onLine)
const update = () => (online.value = navigator.onLine)

onMounted(() => {
  window.addEventListener('online', update)
  window.addEventListener('offline', update)
})
onBeforeUnmount(() => {
  window.removeEventListener('online', update)
  window.removeEventListener('offline', update)
})
</script>

<template>
  <InlineAlert v-if="!online" tone="warning" class="offline">{{ t('offline.banner') }}</InlineAlert>
</template>

<style scoped>
.offline {
  margin-bottom: var(--space-4);
}
</style>
