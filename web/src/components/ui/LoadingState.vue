<script setup lang="ts">
import { useI18n } from 'vue-i18n'

defineProps<{ label?: string }>()
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
  width: 2.5rem;
  height: 0.375rem;
  border-radius: 999px;
  background: linear-gradient(90deg, var(--sky-200), var(--sky-400), var(--sky-200));
  background-size: 200% 100%;
  animation: slide 1.2s linear infinite;
}

@keyframes slide {
  to {
    background-position: -200% 0;
  }
}
</style>
