<script setup>
import { useI18n } from 'vue-i18n'

defineProps({ label: { type: String, default: undefined } })
const { t } = useI18n()
</script>

<template>
  <p class="loading" role="status" aria-live="polite">
    <span class="loading__bar" aria-hidden="true" />
    {{ label ?? t('app.loading') }}
  </p>
</template>

<style scoped>
.loading {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  color: var(--ink-muted);
  padding: var(--space-4) 0;
}

.loading__bar {
  width: 1rem;
  height: 1rem;
  border: 3px solid var(--sky-200);
  border-top-color: var(--primary);
  border-radius: 50%;
  animation: spin 0.9s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
</style>
